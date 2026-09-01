# CAMERA_IO

Ürünün temel hedeflerinden biri **fiziksel kamera üreticisinden bağımsız** olmaktır:
MacBook dahili kamera, USB webcam, harici capture card, Windows laptop kamerası, herhangi
bir UVC uyumlu cihaz.

⚠️ **Mevcut durum bu hedefin çok gerisinde.**

## Mevcut implementasyon (macOS)

`apps/macos/EyesOn/CameraManager.swift`

```swift
AVCaptureDevice.default(for: .video)     // ← tek satır, seçim yok
```

| Özellik | Durum | Not |
|---|---|---|
| Camera enumeration | ❌ **Not implemented** | `AVCaptureDevice.DiscoverySession` kullanılmıyor |
| Camera selection | ❌ **Not implemented** | Her zaman sistem varsayılanı açılır |
| Device ID saklama | ❌ **Not implemented** | Kullanıcı tercihi kalıcı değil |
| Çözünürlük seçimi | ❌ Sabit | `sessionPreset = .hd1280x720` |
| FPS ayarı | ❌ **Not set** | Cihaz varsayılanı kullanılıyor |
| Piksel formatı | ❌ **Not set** | `videoSettings` hiç atanmıyor → AVFoundation varsayılanı. **TODO: verify** hangi format geliyor |
| Aynalama (mirroring) | ❌ **Not set** | `connection.isVideoMirrored` ayarlanmıyor |
| Reconnect davranışı | ❌ **Not implemented** | Kamera çıkarılırsa ne olacağı ele alınmıyor |
| Disconnect handling | ❌ **Not implemented** | `AVCaptureSessionRuntimeError` dinlenmiyor |
| Çoklu kamera | ❌ Kapsam dışı | — |

**Uygulanmış olanlar:**

| Özellik | Durum | Nerede |
|---|---|---|
| İzin akışı | ✅ | `CameraViewModel.start()` — `authorized` / `notDetermined` / `denied` |
| İzin reddi ekranı | ✅ | `PermissionDeniedView.swift` |
| Kamera yok durumu | ✅ | `cameraState = .unavailable`, kullanıcıya mesaj |
| Geç kare atma | ✅ | `alwaysDiscardsLateVideoFrames = true` |
| Info.plist açıklaması | ✅ | `INFOPLIST_KEY_NSCameraUsageDescription` (Türkçe) |
| Sandbox entitlement | ✅ | `com.apple.security.device.camera` |

## Platform API'leri

### macOS — AVFoundation
- Enumeration: `AVCaptureDevice.DiscoverySession(deviceTypes:mediaType:position:)`
  - İlgili tipler: `.builtInWideAngleCamera`, `.external`, `.continuityCamera`, `.deskViewCamera`
- Format: `AVCaptureDevice.formats` → `activeFormat`
- FPS: `activeVideoMinFrameDuration` / `activeVideoMaxFrameDuration`
- Bağlantı olayları: `AVCaptureDevice.wasConnectedNotification` / `wasDisconnectedNotification`
- Aynalama: `AVCaptureConnection.isVideoMirrored`

⚠️ macOS'ta App Sandbox açık (`com.apple.security.app-sandbox = true`). Harici USB
kameralar için ek bir entitlement gerekip gerekmediği **doğrulanmalı** — TODO: verify.

### Windows — planlanan (MVP 8)
- Media Foundation: `IMFActivate` ile cihaz enumeration
- DirectShow: eski cihazlar/uygulamalar için gerekebilir
- UVC uyumlu cihazlar her ikisinde de görünür

### iOS/iPadOS ve Android — planlanan (MVP 9–10)
- iOS: AVFoundation (macOS ile büyük ölçüde aynı API)
- Android: CameraX (Camera2 üzerine)

## Kamera bağımsızlığının gerçek zorlukları

Farklı kameralar aynı sahneyi farklı verir. Bakış tahmini bunlara duyarlıdır:

| Değişken | Etkisi | Ele alma |
|---|---|---|
| **Odak uzaklığı / FOV** | 3B geometri yöntemi (Yöntem B) odak uzaklığına doğrudan bağlıdır | Kalibrasyon veya cihaz başına varsayılan |
| **Çözünürlük** | Landmark hassasiyeti düşer | Minimum çözünürlük eşiği |
| **Kamera konumu** | `kamera_offset` varsayılanı (0, −21, −1) dizüstü içindir; harici webcam farklı yerdedir | Kullanıcı ayarı |
| **Aynalama** | Ters aynalama bakış yönünü **ters çevirir** | Açıkça ayarla, varsayma |
| **Renk/beyaz dengesi** | Iris tespiti etkilenir | MediaPipe genelde dayanıklı |
| **Otomatik pozlama** | Işık dalgalanması → landmark jitter | Temporal smoothing |
| **Capture card** | Genelde 1080p+, farklı gecikme | Format sözleşmesi |

Bunlardan **odak uzaklığı ve kamera konumu**, 3B geometri yöntemine geçilirse (MVP 7)
kritik hale gelir. Yöntem A (iris offset) bunlara duyarsızdır — bu, MVP 3'te A ile
başlamanın bir avantajıdır.

## MVP 1'in kapsamı

[ROADMAP.md](ROADMAP.md#mvp-1--temel-doğrulama--kamera-io) — kamera enumeration, cihaz
seçimi arayüzü, seçimin kalıcı saklanması, disconnect/reconnect davranışı, ve piksel
formatı + aynalamanın açıkça ayarlanması.
