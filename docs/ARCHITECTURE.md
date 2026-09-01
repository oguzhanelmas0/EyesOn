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
      │ 32BGRA sabit, AsyncStream(newest 1) │
      └────────────────┬────────────────────┘
                       │ CMSampleBuffer
                       ↓
      ┌─────────────────────────────────────┐
      │ Landmark Detection                  │  Vision/ONNXFaceLandmarker.swift
      │ MediaPipe Face Landmarker, 478 pts  │  ONNX Runtime
      │ (yedek: Apple Vision)               │  VisionProcessor.swift
      └────────────────┬────────────────────┘
                       │ [Landmark3D] → adapter
                       ↓
      ┌─────────────────────────────────────┐
      │ Source-agnostic geometry            │  Core/MediaPipeFaceAdapter.swift
      │ FaceGeometry: kontur, iris, anchor  │  Core/VisionFaceAdapter.swift
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Validation Gate                     │  Vision/LandmarkValidator.swift
      │ yüz boyutu, EAR, yaw/pitch, IED     │
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Smoothing (EMA)                     │  Core/EMAFilter.swift
      │ landmark α=0.6, blend α=0.3         │
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Gaze Estimation — iki yöntem        │  Core/IrisGazeEstimator.swift
      │ A: iris offset   B: 3B geometri     │  Core/GazeGeometry3D.swift
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Behaviour FSM                       │  Core/BehaviorFSM.swift
      │ 4 durum, histerezis, fade → blend   │
      └────────────────┬────────────────────┘
                       │ CorrectionPlan
                       ↓
      ┌─────────────────────────────────────┐
      │ Eye Contact Correction              │  Core/GazePipeline.swift
      │ • DeepWarp modeli (varsayılan)      │  Core/DeepWarpModel.swift  ← ONNX
      │ • geometrik rijit taşıma (yedek)    │  EyeCorrectionProcessor.swift
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Masked Blending                     │  EyeCorrectionProcessor.swift
      │ convex hull + Gaussian feather      │  Core Image
      │ → göz kapakları orijinale sabit     │
      └────────────────┬────────────────────┘
                       ↓
      ┌─────────────────────────────────────┐
      │ Renderer → SwiftUI Window           │  CameraViewModel.render()
      │ ⚠️ SON DURAK — çıktı burada biter   │
      └─────────────────────────────────────┘

              ╳ Virtual Camera — NOT IMPLEMENTED (MVP 5)
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
| **Landmark (birincil)** | `Vision/ONNXFaceLandmarker.swift` | `CVPixelBuffer` | 478 × `Landmark3D` | ONNX Runtime |
| Landmark (yedek) | `VisionProcessor.swift` | `CVPixelBuffer` | `[VNFaceObservation]` | Vision |
| **Göz düzeltme modeli** | `Core/DeepWarpModel.swift` | göz kırpması + anchor + açı | 48×64×3 düzeltilmiş göz | ONNX Runtime |
| Correction + blending | `EyeCorrectionProcessor.swift` | `CorrectionPlan` + `CIImage` | `CIImage` | Core Image |
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

Toplam ~3200 satır Swift (24 dosya). Tek uygulama target'ı, test target'ı yok.
Metal shader'ı kaldırıldı (EXP-005) — tüm görüntü işleme Core Image ve ONNX üzerinden.

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
