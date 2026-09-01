# MODEL_PIPELINE

## Mevcut modeller

| Component | Model | Runtime | Input | Output | Device |
|---|---|---|---|---|---|
| Face detection | Apple Vision (dahili, sürüm açıklanmaz) | Vision.framework | `CVPixelBuffer` | `[VNFaceObservation]` | Apple tarafından yönetilir (CPU/GPU/ANE) |
| Face landmarks | Apple Vision `VNDetectFaceLandmarksRequest` | Vision.framework | `CVPixelBuffer` + face box | `VNFaceLandmarks2D` (göz, pupil, kaş, ağız…) | Apple tarafından yönetilir |
| Head pose | Apple Vision (`observation.yaw`, `.pitch`) | Vision.framework | — | radyan | — |
| Gaze estimation | **Model yok** — geometrik hesap | Swift | landmarks | `GazeEstimate` | CPU |
| Eye correction | **Model yok** — Metal shader | Metal / Core Image | `CIImage` | `CIImage` | GPU |
| Segmentation | Yok | — | — | — | — |

**Özet: bugün projede hiçbir özel ML modeli yoktur.** Tek ML bileşeni Apple Vision'ın
kapalı kutu modelleridir. `models/` klasörü boştur.

Bunun sonucu: **model export zinciri yoktur.** PyTorch, ONNX, TensorRT, CoreML —
hiçbiri kullanılmıyor. `Examples/EyesOnAI` içinde bir venv vardı (torch + coremltools)
ama proje kodu hiç yazılmamıştı ve o klasör silinecek.

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
| Ağırlıklar | ⚠️ **Elimizde yok** — indirilmeli veya eğitilmeli |
| Format | TF1 checkpoint (sol ve sağ göz için ayrı) |
| Boyut | Küçük — en geniş katman 64 kanal |

Mimari detayı: [EYE_CONTACT.md](EYE_CONTACT.md#28-öğrenilmiş-warp--deepwarp-mvp-7)

## Planlanan export zinciri (MVP 7)

```
TF1 checkpoint  ──►  ONNX  ──┬──►  CoreML          (macOS, iOS/iPadOS)
                             ├──►  ONNX Runtime    (Windows, DirectML/CPU)
                             └──►  TFLite          (Android, NNAPI/GPU delegate)
```

**Neden ONNX ara format:** tek dönüşüm doğrulaması, dört hedef. Alternatif olarak
her hedef için ayrı dönüşüm yapmak dört kez doğrulama demektir.

⚠️ Bu zincir henüz **kurulmadı ve test edilmedi.** TF1 checkpoint → ONNX dönüşümü
`tf2onnx` ile mümkündür ama `spatial_transform.py` içindeki özel bilinear örnekleme
katmanının dönüşümü doğrulanmalıdır — **TODO: verify.**

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
