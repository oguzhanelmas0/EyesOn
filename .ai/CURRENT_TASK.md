# Current Task

**Son güncelleme:** 2026-09-01 · **Agent:** Gemini (Antigravity)

## Goal

MVP 2'yi tamamlamak: MediaPipe 478-nokta (10 iris noktası dahil) Face Landmarker modelini
macOS uygulamasına bağlamak, Apple Vision'ın kaba pupil tespiti yerine milimetrik iris
takibini aktif etmek ve `GazePipeline`'a entegre etmek.

## User-visible Result

Uygulama debug ekranında her iki gözün irisi üzerinde 5'er nokta ve iris çemberi görünür.
Bakış açısı ve iris sapması tam hassasiyetle hesaplanır, göz hareketiyle tam uyumlu
düzeltme uygulanır.

## Current Pipeline Context

Pipeline Aşaması 5 (Landmark Detection) & Aşama 7 (Gaze Estimation).

## Current State

- MediaPipe `face_landmarks_detector.tflite` modeli ONNX formatına dönüştürüldü (`models/face_landmarks_detector.onnx`).
- Apple Silicon üzerinde ortalama 2.3 ms çıkarım süresi doğrulandı.
- SPM `onnxruntime-swift-package-manager` entegrasyonu ve Swift çıkarım katmanı yazılıyor.

## Plan

- [x] TFLite modelini ONNX formatına dönüştür ve çıkarım gecikmesini doğrula
- [ ] Xcode projesine `onnxruntime` paket bağımlılığını ve model dosyasını ekle
- [ ] `ONNXFaceLandmarker.swift` (çıkarım ve 478 nokta üretici) sınıfını yaz
- [ ] `MediaPipeFaceAdapter.swift` (478 noktayı `FaceGeometry`'ye dönüştürücü) yaz
- [ ] `VisionProcessor.swift` ve `CameraViewModel.swift` akışına bağla
- [ ] `LandmarkDebugOverlay.swift` ile iris noktalarını ve çemberlerini çiz
- [ ] `xcodebuild` ile derleme ve çalışma testini doğrula

## Progress

ONNX modeli hazırlandı, Swift entegrasyonu başladı.

