# ARCHITECTURE

Bu dosya **repository'de bugün gerçekten var olan** sistemi anlatır. Planlanan yapı
ayrıca işaretlenmiştir.

## Mevcut sistem (macOS)

```
                 Physical Camera
                 (AVCaptureDevice.default — SEÇİM YOK)
                        ↓
      ┌─────────────────────────────────────┐
      │ Capture Layer                       │  CameraManager.swift
      │ AVCaptureSession, .hd1280x720       │  AVFoundation
      │ AsyncStream, bufferingNewest(1)     │
      └────────────────┬────────────────────┘
                       │ CMSampleBuffer
                       ↓
      ┌─────────────────────────────────────┐
      │ Frame Processor                     │  CameraViewModel.swift
      │ tek async döngü, kare kare          │  Combine + Swift Concurrency
      └────────────────┬────────────────────┘
                       │ CVPixelBuffer
                       ↓
      ┌─────────────────────────────────────┐
      │ Face Detector + Landmark Tracker    │  VisionProcessor.swift (actor)
      │ VNSequenceRequestHandler            │  Apple Vision
      │ VNDetectFaceLandmarksRequest        │
      └────────────────┬────────────────────┘
                       │ [VNFaceObservation] + CIImage
                       ↓
      ┌─────────────────────────────────────┐
      │ Validation Gate                     │  Vision/LandmarkValidator.swift
      │ yüz boyutu, EAR, yaw/pitch, IED     │
      └────────────────┬────────────────────┘
                       │ isSafe: Bool
                       ↓
      ┌─────────────────────────────────────┐
      │ Gaze Estimation                     │  GazeEstimator.swift
      │ pupil − göz centroid, normalize     │
      │ → 5 ayrık yön + sürekli offset      │
      └────────────────┬────────────────────┘
                       │ GazeEstimate
                       ↓
      ┌─────────────────────────────────────┐
      │ Temporal Stabilizer (kısmi)         │  GazeSmoother (GazeEstimator.swift içinde)
      │ 6 karelik mod filtresi              │  ⚠️ yalnız ayrık etiket için
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Eye Contact Correction              │  EyeCorrectionProcessor.swift
      │ Gaussian warp                       │  EyeWarpKernel.swift
      │ ⚠️ varsayılan KAPALI                │  GaussianEyeWarp.metal (CIWarpKernel)
      └────────────────┬────────────────────┘
                       │ CIImage
                       ↓
      ┌─────────────────────────────────────┐
      │ Renderer                            │  CameraViewModel.render()
      │ CIContext(mtlDevice) → CGImage      │  Core Image + Metal
      │ → NSImage                           │
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ SwiftUI Window                      │  ContentView.swift + overlay'ler
      │ ⚠️ SON DURAK — çıktı burada biter   │
      └─────────────────────────────────────┘

              ╳ Virtual Camera — NOT IMPLEMENTED
              ╳ Zoom / Meet / Teams — ulaşılamıyor
```

## Modüller

| Modül | Dosya | Input | Output | Kütüphane |
|---|---|---|---|---|
| Capture | `CameraManager.swift` (77) | — | `CMSampleBuffer` akışı | AVFoundation |
| Preview | `CameraPreviewView.swift` (53) | `AVCaptureSession` | NSView katmanı | AVFoundation, AppKit |
| Orchestrator | `CameraViewModel.swift` (151) | kare akışı | `@Published` durum | Combine, Swift Concurrency |
| Face/Landmark | `VisionProcessor.swift` (32) | `CVPixelBuffer` | `[VNFaceObservation]`, `CIImage` | Vision |
| Validation | `Vision/LandmarkValidator.swift` (162) | `VNFaceObservation` | `LandmarkValidationResult` | Vision |
| Gaze | `GazeEstimator.swift` (153) | `VNFaceObservation` | `GazeEstimate` (yön + offset) | Vision, CoreGraphics |
| Correction | `EyeCorrectionProcessor.swift` (156) | `CIImage` + gaze + validation | `CIImage` | Core Image, Vision |
| Warp kernel yükleyici | `EyeWarpKernel.swift` (64) | `default.metallib` | `CIWarpKernel` | Core Image |
| Warp shader | `GaussianEyeWarp.metal` (33) | piksel koordinatı | kaynak koordinatı | Metal |
| Koordinat dönüşümü | `VisionCoordinateMapper.swift` (90) | normalize nokta | piksel (CIImage / view) | CoreGraphics, Vision |
| **Sabitler** | `Core/CorrectionConfig.swift` | — | tüm eşikler | — |
| **Geometri tipleri** | `Core/FaceGeometry.swift` | — | kaynak-bağımsız `FaceGeometry` | CoreGraphics |
| **Yumuşatma** | `Core/EMAFilter.swift` | `FaceGeometry` | yumuşatılmış `FaceGeometry` | — |
| **Davranış FSM** | `Core/BehaviorFSM.swift` | bakış açısı + kafa pozu | `blend ∈ [0,1]` | — |
| **Bakış — Yöntem A** | `Core/IrisGazeEstimator.swift` | `FaceGeometry` | `GazeInfo` | — |
| **Bakış — Yöntem B** | `Core/GazeGeometry3D.swift` | `FaceGeometry` | `GazeGeometryResult` | — |
| **Vision adaptörü** | `Core/VisionFaceAdapter.swift` | `VNFaceObservation` | `FaceGeometry` | Vision |
| **Boru hattı** | `Core/GazePipeline.swift` | `FaceGeometry` | `CorrectionPlan` | QuartzCore |
| UI | `ContentView.swift` | ViewModel | ekran | SwiftUI |
| UI overlay | `FaceOverlayView.swift` (65), `GazeDirectionView.swift` (72), `LandmarkDebugOverlay.swift` (208) | gözlemler | debug çizimi | SwiftUI |
| İzin ekranı | `PermissionDeniedView.swift` (35) | — | ekran | SwiftUI |
| App girişi | `EyesOnApp.swift` (17) | — | `WindowGroup` | SwiftUI |

Toplam ~2400 satır Swift + Metal. Tek uygulama target'ı, test target'ı yok.

`Core/` altındaki hiçbir dosya Vision'a bağımlı değildir — `VisionFaceAdapter` tek
köprüdür. ADR-001 uygulandığında yerine bir `MediaPipeFaceAdapter` konur ve alt katmanda
hiçbir şey değişmez. Bu, çekirdeğin ileride `core/` klasörüne çıkarılabilmesinin de ön
koşuludur.

## Koordinat sistemleri

Üç farklı koordinat uzayı var ve karıştırmak sessiz hatalara yol açar
(`VisionCoordinateMapper.swift` bu iş için var):

| Uzay | Aralık | Orijin |
|---|---|---|
| Vision normalize | [0, 1] | **sol-alt** |
| CIImage piksel | piksel | **sol-alt** |
| SwiftUI view piksel | piksel | **sol-üst** |

Ayrıca landmark noktaları yüz kutusuna **göreli** normalize gelir — tam görüntü
koordinatına çevirmek için `faceBox.minX + pt.x * faceBox.width` gerekir.

⚠️ `EyeCorrectionProcessor.swift` bu dönüşümleri `VisionCoordinateMapper` yerine **kendi
private yardımcılarıyla** yapıyor (`eyeCentroid`, `pixelRect`, `pupilPixelCenter`).
İki farklı yerde aynı matematiğin olması bir tutarsızlık riskidir.

## Planlanan mimari (MVP 2+)

Yol gösterici ilke: **algoritma bir kez yazılır, platform katmanları ince tutulur.**
Landmark → bakış → warp zinciri beş platformda da matematiksel olarak aynıdır. Gerçekten
değişen üç şey vardır: kareyi nereden alıyoruz, nereye veriyoruz, çıkarımı hangi runtime
yapıyor.

```
┌───────────────────────────────────────────────────────────────┐
│  PLATFORM KATMANI (her OS için ayrı, ince)                    │
│  • Kare kaynağı:  AVFoundation / Media Foundation / Camera2    │
│  • Kare hedefi:   Camera Extension / MF Virtual Cam / uygulama │
│  • Arayüz:        SwiftUI / WinUI / SwiftUI / Compose          │
└───────────────────────┬───────────────────────────────────────┘
                        │  kare girer, kare çıkar
┌───────────────────────▼───────────────────────────────────────┐
│  ÇEKİRDEK (paylaşılan, platformdan bağımsız)                  │
│  1. Landmark    → MediaPipe Face Landmarker (478 + iris)       │
│  2. Doğrulama   → düzeltmek güvenli mi?                        │
│  3. Bakış       → iris offset + head pose → açı                │
│  4. Davranış    → 4 durumlu FSM: ne zaman düzelt, ne zaman çekil│
│  5. Yumuşatma   → EMA filtreleri                               │
│  6. Warp        → geometrik (MVP 4) → öğrenilmiş model (MVP 7)  │
│  7. Harmanlama  → maske + feather                              │
└────────────────────────────────────────────────────────────────┘
```

Adım 1 ve 6 model çalıştırır; platform başına farklı runtime kullanabilirler
(CoreML / TFLite / ONNX Runtime) ama **girdi-çıktı sözleşmesi aynı kalır.** Kalan beş
adım saf matematiktir ve tek bir yerde yaşamalıdır.

### `core/` neden şimdilik boş

Çekirdeğin hangi dilde yazılacağı, macOS'ta MediaPipe'ı nasıl çalıştırdığımıza bağlı ve
o soru açık (ADR-002). İki ihtimal: **C++ çekirdek** (MediaPipe'ı zaten C++ bağlıyorsak
doğal seçim, beş platformda tek kod, bedeli köprü kodu) veya **platform başına port**
(algoritma `EYE_CONTACT.md`'de tek doğruluk kaynağı olarak yaşar, her platform kendi
dilinde uygular, bedeli dört kez yazmak).

Karar MVP 5'in sonunda, Windows'a başlamadan hemen önce verilecek — o noktada MediaPipe
entegrasyonunun gerçek maliyeti bilinir olur. Bu bilinçli bir ertelemedir; erken
soyutlama yapmıyoruz.
