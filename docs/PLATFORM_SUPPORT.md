# PLATFORM_SUPPORT

## Durum matrisi

| Platform | Capture | Processing | GPU | Virtual Camera | Status |
|---|---|---|---|---|---|
| **macOS (Apple Silicon)** | ✅ AVFoundation | ⚠️ Kısmi (tespit ✅, düzeltme deneysel) | ✅ Metal / Core Image | ❌ Not implemented | **Aktif geliştirme** |
| **macOS (Intel)** | ✅ Aynı kod | ⚠️ Aynı | ✅ Metal | ❌ | Test edilmedi |
| **Windows (NVIDIA)** | ❌ | ❌ | ❌ | ❌ | Planlı — MVP 8 |
| **Windows (iGPU)** | ❌ | ❌ | ❌ | ❌ | Planlı — MVP 8 |
| **iOS** | ❌ | ❌ | ❌ | 🚫 **Mümkün değil** | Planlı — MVP 9 |
| **iPadOS** | ❌ | ❌ | ❌ | 🚫 **Mümkün değil** | Planlı — MVP 9 |
| **Android (telefon)** | ❌ | ❌ | ❌ | 🚫 **Pratikte mümkün değil** | Planlı — MVP 10 |
| **Android (tablet)** | ❌ | ❌ | ❌ | 🚫 **Pratikte mümkün değil** | Planlı — MVP 10 |

**Not:** macOS Intel'de kod aynıdır ama hiç test edilmemiştir. Metal shader'ı ve
`CIContext(mtlDevice:)` yolu Intel Mac'lerde de çalışmalıdır — **TODO: verify.**

---

## Temel gerçek: sanal kamera masaüstünde var, mobilde yok

"Zoom'a girdiğimde gözüm kameraya baksın" cümlesi teknik olarak şu demektir: *kamera
görüntüsünü Zoom'a ulaşmadan önce değiştirebilmek.* Bunun tek yolu işletim sisteminin
**sanal kamera** mekanizmasıdır ve bu mekanizma masaüstünde vardır, mobilde yoktur.

Sonuç: **EyesOn masaüstünde bir sistem aracı, mobilde bir uygulama/SDK olacaktır.**
İki farklı ürün şekli, tek algoritma çekirdeği. Bu bir eksiklik değil, platform
gerçeğidir.

---

## macOS

**Minimum sürüm:** projede `MACOSX_DEPLOYMENT_TARGET = 26.3` ayarlı. Camera Extension
macOS 13+ gerektirir, yani bu tarafta kısıt yok.

| Bileşen | Teknoloji |
|---|---|
| Capture | AVFoundation |
| Landmark | Apple Vision → MediaPipe (ADR-001) |
| GPU | Metal, Core Image (`CIContext(mtlDevice:)`) |
| Virtual camera | CMIOExtension (system extension) |
| UI | SwiftUI + AppKit köprüleri |
| Dağıtım | Developer ID + notarization; App Store dışı |

**Neden App Store dışı:** system extension kurulumu App Store dağıtımıyla çelişir.
**TODO: verify** — bu kesin bir kısıt mı, yoksa özel entitlement ile mümkün mü.

## Windows

**Hedef:** Windows 10 ve 11.

| Bileşen | Teknoloji |
|---|---|
| Capture | Media Foundation (UVC cihazlar), gerekirse DirectShow |
| Landmark | MediaPipe (C++ / ONNX Runtime) |
| GPU | DirectML (ONNX Runtime sağlayıcısı) veya D3D11 compute; CPU fallback |
| Virtual camera | `MFCreateVirtualCamera` (Win11 22H2+) **ve** DirectShow filtresi (Win10 + eski uygulamalar) |
| UI | TODO — WinUI 3 / Qt / Electron kararı verilmedi |

**Neden iki sanal kamera API'si:** Zoom/Teams'in hangisini kullandığı sürüme göre
değişir. Windows 10 desteği istiyorsak DirectShow zorunlu.

**NVIDIA vs iGPU:** NVIDIA Broadcast RTX gerektirir; biz gerektirmemeliyiz. Bu bir
farklılaşma noktasıdır — modeller küçük olduğu için iGPU'da, hatta CPU'da çalışmalıdır.

## iOS / iPadOS

**Sistem çapında sanal kamera mümkün değildir. İstisna yoktur.**

Apple, bir uygulamanın başka bir uygulamanın kamera akışına müdahale etmesine izin
vermez. Bu bir API eksikliği değil, bilinçli bir güvenlik sınırıdır ve değişmesini
beklemek gerçekçi değildir.

Gerçekçi seçenekler:

| Seçenek | Artı | Eksi |
|---|---|---|
| **1. Kendi görüntülü görüşme uygulamamız** | Tam kontrol, uçtan uca deneyim | Zoom/Teams'in yerini almak zorundayız — çok zor pazar |
| **2. SDK / kütüphane** | Başka uygulamalara gömülür; WebRTC video işlemci hattına takılır. B2B model | Tek başına kullanıcıya satılamaz |
| **3. Broadcast Upload Extension** | — | **Kamerayı değiştiremez**, sadece ekran paylaşımını. Senaryomuza uymuyor |

**Önerilen yön: 2 (SDK).** Ancak bu bir **ürün stratejisi kararıdır**, teknik karar
değil. Masaüstü sürümü insanlarda işe yarayıp yaramadığını gösterene kadar vermeye
gerek yok.

**Teknik taraf kolay:** iOS'ta AVFoundation macOS ile neredeyse aynı, MediaPipe'ın iOS
desteği birinci sınıf (resmî CocoaPod), CoreML zaten hedef. Zorluk teknikte değil,
dağıtım modelinde.

## Android

Resmî sanal kamera API'si yoktur. Dolaşan çözümler root, Xposed/LSPosed modülleri veya
OEM'e özel arka kapılar kullanır — hiçbiri Play Store'a giremez ve normal kullanıcıya
sevk edilemez.

Yani iOS ile aynı sonuç: **kendi uygulama veya SDK.**

**Teknik taraf rahat:** MediaPipe'ın Android desteği birinci sınıf (resmî AAR),
TFLite + NNAPI/GPU delegate ile warp modeli sorunsuz çalışır. CameraX capture'ı
basitleştirir.

**Android tablet** telefondan farklı değildir — aynı kod, farklı ekran boyutu.
`kamera_offset` varsayılanı cihaz sınıfına göre değişmelidir (tablet kamerası genelde
kenarda, telefon üstte).

---

## Sıralama gerekçesi

```
MVP 1–6   ─►  macOS       : sanal kamera var, ürün gerçekten çalışıyor
MVP 7     ─►  Model       : kalite sıçraması, platform bağımsız kazanç
MVP 8     ─►  Windows     : aynı ürün şekli, aynı değer önerisi, en büyük pazar
MVP 9–10  ─►  iOS/Android : farklı ürün şekli — önce strateji, sonra kod
```

Masaüstünü önce bitirmemizin sebebi sadece elimizde Mac olması değil: **masaüstünde
ürün gerçekten çalışıyor.** Mobilde ne yapacağımız bir ürün sorusudur ve cevabı,
masaüstü sürümünün gerçek kullanıcılarda işe yarayıp yaramadığını gördükten sonra
çok daha net olur.
