# MODEL_PIPELINE

## Mevcut modeller

| Component | Model | Runtime | Input | Output | Device |
|---|---|---|---|---|---|
| Face detection | Apple Vision (dahili) | Vision.framework | `CVPixelBuffer` | `[VNFaceObservation]` | Apple yönetir (CPU/GPU/ANE) |
| **Face landmarks** | **MediaPipe Face Landmarker** | **ONNX Runtime** | 256×256 yüz kırpması | **478 3B nokta (iris dahil)** | CPU (2 thread) |
| Face landmarks (yedek) | Apple Vision `VNDetectFaceLandmarksRequest` | Vision.framework | `CVPixelBuffer` + face box | `VNFaceLandmarks2D` | Apple yönetir |
| Head pose | Apple Vision (`observation.yaw`, `.pitch`) | Vision.framework | — | radyan | — |
| Gaze estimation | **Model yok** — geometrik hesap | Swift | `FaceGeometry` | `GazeInfo` + açı | CPU |
| **Eye correction** | **DeepWarp** (L/R ayrı) | **ONNX Runtime** | 48×64×3 + 48×64×12 + 2 | 48×64×3 | CPU |
| Blending | Model yok — maske | Core Image | `CIImage` | `CIImage` | GPU |
| Segmentation | Yok | — | — | — | — |

**Güncel durum (2026-09-01):** Proje artık ONNX Runtime çalıştırıyor.
`models/face_landmarks_detector.onnx` MediaPipe Face Landmarker'ı sağlıyor
(`Vision/ONNXFaceLandmarker.swift` → `Core/MediaPipeFaceAdapter.swift`).

Göz düzeltme modeli (DeepWarp) henüz boru hattında değil, ama **ağırlıkları elimizde**:
`models/deepwarp/weights/warping_model/flx/12/{L,R}` — sol/sağ göz için ayrı TF1
checkpoint'leri, toplam ~6 MB.

## Planlanan modeller

### MVP 2 — MediaPipe Face Landmarker

| Alan | Değer |
|---|---|
| Model | `face_landmarker.task` (MediaPipe Tasks bundle) |
| İçerik | Face detector (BlazeFace short-range) + face mesh + iris (attention mesh) + blendshapes |
| Çıktı | 478 landmark (x, y, z normalize) — 468 yüz + 10 iris |
| Boyut | ~3–4 MB **TODO: verify** |
| Runtime | ⚠️ **Açık soru** → ADR-002 |
| Cihaz | GPU delegate tercih edilir, CPU fallback |

Runtime seçenekleri ve neden henüz karar verilmediği: `.ai/DECISIONS.md` ADR-002.

### MVP 7 — DeepWarp göz düzeltme modeli

| Alan | Değer |
|---|---|
| Mimari | DeepWarp (coarse-to-fine flow + light correction module) |
| Kaynak | `reference/deepwarp-cam/tf_models/gaze_corrector_v1/` |
| Makale | Hsu et al., ACM TOMM 15(2), 2019 |
| Girdi | 48×64×3 göz görüntüsü + 48×64×12 anchor map + 2 açı |
| Çıktı | 48×64×3 düzeltilmiş göz |
| Ağırlıklar | ✅ **Elimizde** — `models/deepwarp/weights/warping_model/flx/12/{L,R}` |
| Format | TF1 checkpoint → **ONNX** (sol ve sağ göz için ayrı, ~1.05 MB) |
| Boyut | Küçük — en geniş katman 64 kanal |

Mimari detayı: [EYE_CONTACT.md](EYE_CONTACT.md#28-öğrenilmiş-warp--deepwarp-mvp-7)

## Planlanan export zinciri (MVP 7)

```
TF1 checkpoint  ──►  ONNX  ──┬──►  ONNX Runtime    (macOS ✅ mevcut, Windows)
                             ├──►  CoreML          (iOS/iPadOS — ileride)
                             └──►  TFLite          (Android, NNAPI/GPU delegate)
```

**macOS için CoreML adımı gerekmiyor:** ONNX Runtime ADR-002 ile zaten projede.
Bu, MVP 7'yi tek bir dönüşüme indiriyor: TF1 → ONNX.

✅ **Doğrulandı (2026-09-01, EXP-007).** TF1 → ONNX dönüşümü yapıldı ve sayısal olarak
karşılaştırıldı: max abs fark L için 2.1e-05, R için 3.4e-05 — float32 gürültüsü
seviyesinde. Riskli görülen `spatial_transform.py` bilinear örnekleme katmanı sorunsuz
çevrildi.

Dönüşüm betiği: `scratchpad/convert_deepwarp.py` (opset 13, `tf2onnx` 1.17.0).
Çıktı: `models/deepwarp/onnx/deepwarp_{L,R}.onnx`, ~1.05 MB / göz.

## Kural: export zincirini bozma

Bu zincir kurulduktan sonra, model tarafında bir değişiklik yapan agent:

1. Dönüşümü baştan çalıştırmalı
2. Aynı test görüntüsüyle her hedefte çıktıyı karşılaştırmalı (sayısal fark eşiği ile)
3. Sonucu `.ai/EXPERIMENTS.md`'ye kaydetmeli

Bir hedefte çalışıp diğerinde bozulan bir model değişikliği, sessizce ilerlerse çok
pahalıya patlar.

## Model dosyalarının yeri

`models/` — git'e girmez ([models/README.md](../models/README.md)). İndirme talimatları
ve beklenen SHA'lar orada tutulur. Model dosyalarını repository'ye commit etme.
