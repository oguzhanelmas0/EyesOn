# Current Task

**Son güncelleme:** 2026-09-01 · **Agent:** Claude (Opus 5)

## Goal

MVP 7 — DeepWarp modelini entegre etmek. 2D piksel bükmenin kalite tavanını
(iris'te çift görüntü/bulanıklık) öğrenilmiş sentezle aşmak.

## User-visible Result

Gözler yana bakarken bile bulanıklık/hayalet olmadan, fotogerçekçi biçimde kameraya
bakıyor görünür. Gain'i zorlamaya gerek kalmaz.

## Current Pipeline Context

`... → Gaze Estimation → **Eye Contact Correction** → Blending → ...`
Yalnızca düzeltme aşaması değişiyor; landmark, FSM, yumuşatma, maske aynı kalıyor.

## Current State

Hazır olanlar:
- **MediaPipe 478 nokta ONNX üzerinden çalışıyor** (ADR-002 kapandı, Gemini uyguladı).
  Canlı doğrulandı: iris tespiti nokta atışı.
- Davranış FSM'i, EMA yumuşatma, doğrulama kapısı, kontur maskesi çalışıyor.
- **DeepWarp ağırlıkları indirildi:** `models/deepwarp/weights/warping_model/flx/12/{L,R}`
- **ONNX Runtime projede mevcut** — CoreML dönüşümü gerekmiyor.

Eksik: modelin kendisi henüz boru hattında değil.

## Plan

- [x] **1. Sayısal doğrulama** ✅ EXP-007
- [x] **2. TF1 → ONNX dönüşümü** ✅ EXP-007 — L: 2.1e-05, R: 3.4e-05 fark, PASS.
      Modeller `apps/macos/EyesOn/deepwarp_{L,R}.onnx` olarak bundle'a kopyalandı.
- [ ] **3. Swift tarafı:** 48×64 göz kırpması + 12 kanallı anchor map üretimi
- [ ] **4.** `GazeGeometry3D` açısını modele bağla (derece cinsinden, L/R ayrı model)
- [ ] **5.** Çıktıyı mevcut kontur maskesiyle kareye harmanla
- [ ] **6.** Geometrik warp'ı fallback olarak koru
- [ ] **7.** EXP kaydı + görsel karşılaştırma (geometrik vs model)

## Files Involved

Yeni: DeepWarp ONNX oturumu (`Vision/` altında, `ONNXFaceLandmarker` deseni)
Değişecek: `Core/GazePipeline.swift`, `EyeCorrectionProcessor.swift`
Sabit kalacak: landmark, FSM, yumuşatma, maske

## Current Focus

Adım 3–5: Swift entegrasyonu. Model dosyaları bundle'da, dönüşüm doğrulandı.

**Dikkat edilecek nokta:** DeepWarp'ın anchor map'i, dlib-68 eşdeğeri **6 göz noktası**
bekliyor (MediaPipe karşılıkları: sol `[362, 385, 387, 263, 373, 380]`,
sağ `[33, 160, 158, 133, 153, 144]`). Mevcut `MediaPipeFaceAdapter` 16 noktalı kontur
veriyor; `EyeGeometry`'ye ayrıca bu 6 noktalık anchor dizisi eklenmeli.
Anchor sırası L için `[3,2,1,0,5,4]`, R için `[0,1,2,3,4,5]`.

## Experiments Tried

EXP-003 (yayılma → izole yama), EXP-004 (hedef tabanlı warp),
EXP-005 (hayalet → rijit taşıma + maske), EXP-006 (referansları canlı çalıştırma).
Hepsi `.ai/EXPERIMENTS.md` içinde.

## Results

Ölçüm yok — MVP 7 başlamadı. Kalite gözlemi: 2D warp gain yükselince bulanıklaşıyor
(kullanıcı + Gemini bağımsız olarak doğruladı).

## Known Problems

- P5: head pose düzeltme **vektörüne** hâlâ girmiyor (FSM'e giriyor)
- P6/P7: yatay işaret yönü ve aynalama gözle doğrulanmadı
- Sanal kamera hâlâ yok (MVP 5)

## Do Not Change

- ONNX MediaPipe entegrasyonu (yeni, çalışıyor, Gemini'nin işi)
- Davranış FSM'i ve EMA yumuşatma
- Kontur maskesi mantığı — model çıktısı da aynı maskeden geçecek

## Next Action

`models/deepwarp/weights/.../L` checkpoint'ini TensorFlow ile yükleyip tek bir test
göz görüntüsünde çıkarım almak ve referans çıktıyı kaydetmek. Ortam hazır:
`scratchpad/venv-dw` (TF 2.19.1).
