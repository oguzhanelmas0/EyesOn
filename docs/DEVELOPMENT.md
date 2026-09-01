# DEVELOPMENT

## Gereksinimler

| Araç | Sürüm | Not |
|---|---|---|
| macOS | 26.3+ | `MACOSX_DEPLOYMENT_TARGET = 26.3` |
| Xcode | 16+ | Proje `objectVersion 77` (senkronize klasör grupları) kullanıyor |
| Swift | 5.0 | `SWIFT_VERSION = 5.0` |
| git | — | Remote: `github.com/oguzhanelmas0/EyesOn` |

Ek bağımlılık yok: Swift Package Manager paketi, CocoaPods veya Carthage kullanılmıyor.
Tüm kütüphaneler Apple SDK'sından geliyor (AVFoundation, Vision, Core Image, Metal,
SwiftUI, AppKit, Combine).

## Derleme ve çalıştırma

```bash
open apps/macos/EyesOn.xcodeproj
```

Xcode'da `EyesOn` şemasını seçip Run. İlk çalıştırmada macOS kamera izni ister.

Komut satırından:

```bash
xcodebuild -project apps/macos/EyesOn.xcodeproj -scheme EyesOn -configuration Debug build
```

⚠️ Proje bu oturumda kökten `apps/macos/` altına taşındı ve **taşımadan sonra
derlenmedi.** İlk iş bunu doğrulamaktır.

## Uygulamayı kullanma

Arayüzdeki düğmeler:

| Düğme | Etki |
|---|---|
| 🐞 Debug | Tüm debug katmanını aç/kapa |
| □ Yüz | Yüz sınırlayıcı kutusu |
| □ Marks | Landmark noktaları |
| □ ROI | Göz ROI kutuları |
| **⚡ Düzeltme** | **Göz düzeltmesini aç/kapa — varsayılan KAPALI** |

Üstteki durum göstergesi düzeltmenin aktif olup olmadığını ve değilse **sebebini**
gösterir (örn. "Kafa çok dönük (yaw 27°)").

## Kod imzalama

`CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`.
Kendi geliştirici hesabınla otomatik imzalanır.

App Sandbox açık, `com.apple.security.device.camera` entitlement'ı var.

⚠️ MVP 5'te Camera Extension eklendiğinde imzalama gereksinimleri değişecek
(Developer ID + notarization + system extension entitlement) →
[VIRTUAL_CAMERA.md](VIRTUAL_CAMERA.md#macos--camera-extension-cmioextension)

## Metal shader

`GaussianEyeWarp.metal` Xcode tarafından derlenip `default.metallib` olarak bundle'a
konur. `EyeWarpKernel.swift` bunu çalışma zamanında `Bundle.main.url(forResource:
"default", withExtension: "metallib")` ile yükler.

Yüklenemezse konsola `[EyeWarpKernel] ❌ ...` yazar ve CPU fallback'ine düşer.
**Düzeltme çalışmıyorsa ilk bakılacak yer bu konsol çıktısıdır.**

## Klasör yapısı

```
EyesOn/
├── AGENTS.md            # Claude/Codex/Gemini ortak kuralları — ÖNCE BUNU OKU
├── CLAUDE.md            # → AGENTS.md
├── .ai/                 # canlı proje hafızası
│   ├── CURRENT_TASK.md  # aktif görev, nerede kalındı
│   ├── WORKLOG.md       # tamamlanmış işler
│   ├── DECISIONS.md     # ADR'ler
│   └── EXPERIMENTS.md   # denenmiş yöntemler (başarısızlar dahil)
├── docs/                # konu bazlı teknik dokümantasyon
├── apps/macos/          # Xcode projesi
├── core/                # paylaşılan çekirdek (henüz boş)
├── models/              # ML model dosyaları (git'e girmez)
├── reference/           # referans projeler (okumak için, MIT, derlenmez)
└── Examples/            # GEÇİCİ, git'te yok, silinecek — REFERANS VERME
```

## Git

Remote `origin` → `https://github.com/oguzhanelmas0/EyesOn.git`, branch `main`.

`.gitignore` dışlananlar: Xcode kullanıcı verileri, `DerivedData/`, `build/`,
`.DS_Store`, `._*` (exFAT AppleDouble dosyaları), `Examples/`.

**Commit mesajları Türkçe.** Commit ve push yalnızca kullanıcı istediğinde yapılır.

## Yeni bir agent olarak başlıyorsan

[AGENTS.md](../AGENTS.md) → **Resume Protocol** bölümünü uygula. Özetle:

```bash
cat .ai/CURRENT_TASK.md
git status --short
git diff --stat
git log --oneline -10
```

Çalışma ağacındaki değişiklikler senin olmayabilir — silme, ezme, `git reset --hard`
yapma.
