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

- [ ] **1. Sayısal doğrulama (Swift'e dokunmadan):** TF1 checkpoint'i yükle, test göz
      kırpmasıyla çıkarım al, referans çıktıyı kaydet
- [ ] **2. TF1 → ONNX dönüşümü**, özellikle `spatial_transform` bilinear örnekleme
      katmanını doğrula; aynı girdide TF ve ONNX çıktılarını sayısal karşılaştır
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

Adım 1–2: dönüşümün sayısal olarak doğru olduğunu Python'da kanıtlamak.
Bu geçmeden Swift'e dokunulmayacak.

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
