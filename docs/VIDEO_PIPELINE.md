# VIDEO_PIPELINE

Bir karenin baştan sona yaşam döngüsü. Bu dosya **mevcut kodun gerçekte yaptığını**
anlatır; planlanan değişiklikler ayrıca işaretlenmiştir.

## Kare yaşam döngüsü (mevcut)

```
1. Capture          AVCaptureVideoDataOutput → captureOutput(_:didOutput:from:)
                    kuyruk: com.eyeson.capture (DispatchQueue, .userInitiated)
                    ↓ CMSampleBuffer
2. Buffering        AsyncStream.Continuation.yield()
                    bufferingPolicy: .bufferingNewest(1)  ← en yeni 1 kare, gerisi düşer
                    ↓
3. Unwrap           CMSampleBufferGetImageBuffer → CVPixelBuffer
                    ↓
4. Detection        VNSequenceRequestHandler.perform(orientation: .up)
                    VNDetectFaceLandmarksRequest
                    ↓ [VNFaceObservation]
5. Validation       LandmarkValidator.validate(observation)
                    ↓ isSafe / rejectionReason
6. Gaze             GazeEstimator.estimate(from: observation)   ← yalnız isSafe ise
                    ↓ GazeEstimate(direction, rawOffset)
7. Smoothing        GazeSmoother.add(direction)  ← 6 karelik mod filtresi
                    ↓ smoothedDirection
8. Correction       EyeCorrectionProcessor.correct(...)
                    ← koşullar: correctionEnabled && isSafe && direction != .center
                    ↓ CIImage
9. Render           CIContext(mtlDevice:).createCGImage → NSImage
                    ↓
10. Publish         @Published özelliklere yazılır → SwiftUI yeniden çizer
```

## Format ve çözünürlük

| Özellik | Değer | Nerede |
|---|---|---|
| Session preset | `.hd1280x720` | `CameraManager.setup()` |
| Piksel formatı | **Belirtilmemiş** — `AVCaptureVideoDataOutput` varsayılanı | `CameraManager.addVideoOutput()` |
| Hedef FPS | **Ayarlanmamış** — cihaz varsayılanı | — |
| Vision orientation | `.up` | `VisionProcessor.process()` |
| Renk uzayı | `CIImage(cvPixelBuffer:)` ne veriyorsa | `VisionProcessor` |
| Aynalama (mirroring) | **Ayarlanmamış** | — |

⚠️ **TODO: verify** — `videoSettings` hiç set edilmediği için macOS'un hangi piksel
formatını verdiği koddan okunamaz. Camera Extension yazılırken (MVP 5) format sözleşmesi
netleştirilmek zorunda. Ayrıca ön kamera aynalaması ayarlanmadığı için önizlemenin ayna
görüntüsü mü yoksa gerçek yön mü olduğu **gözle doğrulanmalı** — bu, bakış yönü
etiketlerinin (Sol/Sağ) doğru olup olmadığını doğrudan etkiler.

## Threading modeli

**Mevcut: iki iş parçacığı.**

```
[Capture kuyruğu]                    [Frame processing Task]
com.eyeson.capture                   Swift Concurrency (varsayılan executor)
     │                                        │
     │ yield()                                │ for await
     └───────► AsyncStream (buffer: 1) ───────┘
                                              │
                                              ├─ await VisionProcessor (actor)
                                              ├─ CPU: validation, gaze, smoothing
                                              ├─ GPU: CIWarpKernel
                                              ├─ GPU→CPU: createCGImage
                                              └─ @Published yazımı
```

`VisionProcessor` bir `actor` olduğu için Vision çağrıları izole; ancak **6–10. adımların
tamamı tek bir Task içinde sıralı** çalışıyor. Yani render (9) bitmeden bir sonraki kare
işlenmeye başlamıyor.

⚠️ **Bilinen risk:** `@Published` özelliklere `@MainActor` izolasyonu olmadan yazılıyor
(`startFrameProcessing` içindeki Task main actor'a bağlı değil). SwiftUI'ın ana thread
dışından güncellenmesi Swift 6 strict concurrency altında hata verebilir. **TODO: verify** —
derleme uyarısı çıkıyor mu.

**Planlanan (MVP 5):** referans projedeki üç iş parçacıklı yapı
(`reference/gaze-corrector/pipeline.py`):

```
[Capture] ──queue(2)──► [Process] ──queue(2)──► [Output → Virtual Camera]
```

Virtual camera eklendiğinde render ve çıktı ayrı bir iş parçacığına alınmalı; aksi halde
çıktı gecikmesi tespit hattını bloke eder.

## Kare düşürme politikası

**Mevcut, iki yerde:**

1. `videoOutput.alwaysDiscardsLateVideoFrames = true` — AVFoundation seviyesinde
2. `AsyncStream(bufferingPolicy: .bufferingNewest(1))` — uygulama seviyesinde

İkisi de doğru davranış: **işleme yavaşladığında gecikme birikmez, kare düşer.**
Bir video görüşmesinde geç gelen doğru kare, zamanında gelen düzeltilmemiş kareden
kötüdür.

Bu ilke virtual camera eklendiğinde de korunmalıdır — çıktı kuyruğu da sınırlı ve
en-eskiyi-atan olmalı.

## Gecikme kaynakları (henüz ölçülmedi)

Beklenen sıcak noktalar, en pahalıdan ucuza doğru tahmin:

1. `VNDetectFaceLandmarksRequest` — her karede tam tespit
2. `createCGImage` — GPU→CPU kopyası, her karede
3. `CIWarpKernel` — göz başına bir kez, **tüm kare genişliğinde** (bkz.
   [EYE_CONTACT.md](EYE_CONTACT.md#bilinen-kod-problemleri))
4. `NSImage` oluşturma ve SwiftUI yeniden çizimi

⚠️ Bu bir **tahmin sıralamasıdır, ölçüm değildir.** Gerçek profil MVP 1'de Instruments
ile çıkarılacak → [PERFORMANCE.md](PERFORMANCE.md).

Not: virtual camera'ya geçildiğinde `createCGImage` → `NSImage` → SwiftUI zinciri
gereksiz hale gelir; çıktı doğrudan `CVPixelBuffer` olarak verilmelidir. Bu tek başına
anlamlı bir gecikme kazancı olabilir.
