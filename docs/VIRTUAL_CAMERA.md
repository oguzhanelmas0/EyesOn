# VIRTUAL_CAMERA

**Status: Not Implemented**

Bu bileşen olmadan EyesOn bir ürün değil, bir demodur. Konferans uygulamaları hiçbir
şekilde uygulamanın çıktısını göremez.

## Hedef akış

```
Processed Frames  →  Virtual Camera Driver/Interface  →  Zoom / Meet / Teams / Discord
```

## Mevcut durum

`apps/macos/EyesOn/` altında sanal kamera ile ilgili **hiçbir kod yoktur.** İşlenmiş kare
`CameraViewModel.render()` içinde `NSImage`'a dönüştürülüp SwiftUI penceresine basılır ve
orada biter.

## Platform teknolojileri

### macOS — Camera Extension (CMIOExtension)

**Seçilen yol.** macOS 13 Ventura'dan itibaren `CMIOExtension` API'si var.

- Ana uygulamanın içine gömülü bir **system extension** olarak dağıtılır
- Kullanıcı onayıyla etkinleşir, sonra sistemdeki tüm uygulamalara normal bir kamera
  cihazı olarak görünür
- Ayrı bir süreçte çalışır; ana uygulamayla IPC ile konuşur
- Kurulum: `OSSystemExtensionRequest`
- Gerekli entitlement: `com.apple.developer.system-extension.install`
- Kod imzalama zorunlu; dağıtım için Developer ID + notarization

⚠️ Eski **DAL plugin** yolu (Zoom'un yıllarca kullandığı) macOS 12.3'te kaldırıldı.
Kullanma.

⚠️ Mevcut uygulama App Sandbox içinde çalışıyor. System extension kurulumunun sandbox
ile birlikte nasıl çalıştığı **doğrulanmalı** — TODO: verify.

**Prototip kısayolu:** OBS Virtual Camera'yı kullanmak. `reference/gaze-corrector`
bunu yapıyor (`pyvirtualcam` üzerinden). Kullanıcının OBS kurmasını gerektirdiği için
sevkiyata uygun değil, ama MVP 5'ten önce uçtan uca test için işe yarayabilir.

### Windows — iki API, ikisi de gerekebilir (MVP 8)

1. **Media Foundation Virtual Camera** — `MFCreateVirtualCamera`, Windows 11 22H2+.
   Modern, resmî yol.
2. **DirectShow filtresi** — eski ama hâlâ yaygın. Bazı uygulamalar ve eski sürümler
   yalnızca DirectShow kameralarını listeler.

Zoom/Teams'in hangi API'yi kullandığı sürüme göre değişir → **ikisini birden sağlamak**
gerçekçi plandır. Windows 10 desteği istiyorsak DirectShow zorunlu.

### iOS / iPadOS — mümkün değil

Apple, bir uygulamanın başka bir uygulamanın kamera akışına müdahale etmesine izin
vermez. Bu bir API eksikliği değil, bilinçli bir güvenlik sınırıdır.
Detay ve alternatifler: [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md#ios--ipados)

### Android — pratikte mümkün değil

Resmî sanal kamera API'si yoktur. Dolaşan çözümler root, Xposed/LSPosed modülleri veya
OEM'e özel arka kapılar kullanır; hiçbiri Play Store'a giremez.
Detay: [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md#android)

## Belirlenmesi gereken sözleşme

Camera Extension yazılırken netleştirilmesi gerekenler (**hiçbiri henüz kararlaştırılmadı**):

| Konu | Durum |
|---|---|
| Output pixel format | TODO — muhtemelen `kCVPixelFormatType_32BGRA` veya NV12 |
| Output resolution | TODO — girişi mi yansıtacak, sabit mi olacak |
| Output FPS | TODO — 30 hedefi |
| Kare kaynağı yoksa davranış | TODO — siyah kare mi, son kare mi, ham kamera mı |
| Uygulama kapalıyken davranış | TODO — cihaz listede kalmalı mı |
| IPC mekanizması | TODO — XPC / shared memory / IOSurface |
| Kurulum akışı UX'i | TODO — sistem onayı sürtünmeli, iyi tasarlanmalı |

## Bilinen zorluklar

- **Kurulum sürtünmesi** — kullanıcı sistem ayarlarından onay vermeli, bazen yeniden
  başlatma gerekir. İlk açılış akışı bunu iyi yönetmeli
- **Kod imzalama** — Developer ID ve notarization olmadan dağıtılamaz
- **Konferans uygulaması uyumluluğu** — her uygulama sanal kameraları farklı listeler;
  gerçek test gerekir (bkz. [TESTING.md](TESTING.md#7-conferencing-app-tests))
- **Kaynak kullanımı** — extension ayrı süreçte çalışır, bellek/CPU bütçesi ayrıdır
