# DEVELOPMENT

## Gereksinimler

| Araç | Sürüm | Not |
|---|---|---|
| macOS | 26.3+ | `MACOSX_DEPLOYMENT_TARGET = 26.3` |
| Xcode | 16+ | Proje `objectVersion 77` (senkronize klasör grupları) kullanıyor |
| Swift | 5.0 | `SWIFT_VERSION = 5.0` |
| git | — | Remote: `github.com/oguzhanelmas0/EyesOn` |

### Bağımlılıklar

| Paket | Nasıl | Ne için |
|---|---|---|
| `onnxruntime-swift-package-manager` | SPM (Xcode otomatik çözer) | MediaPipe landmark + DeepWarp modelleri |

Geri kalan her şey Apple SDK'sından: AVFoundation, Vision, Core Image, SwiftUI,
AppKit, Combine. İlk derlemede Xcode ONNX Runtime'ı indirir (ağ gerekir).

### Model dosyaları

Uygulama üç `.onnx` dosyasına ihtiyaç duyar ve bunlar repository'de mevcuttur
(`apps/macos/EyesOn/` altında, git'te izleniyor):

- `face_landmarks_detector.onnx` — MediaPipe Face Landmarker (4.7 MB)
- `deepwarp_L.onnx`, `deepwarp_R.onnx` — göz düzeltme modeli (~1.05 MB ×2)

Ayrıca ek indirme gerekmez. Kaynak checkpoint'ler ve dönüşüm için:
[models/README.md](../models/README.md).

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
| **⚡ Düzeltme** | Göz düzeltmesini aç/kapa (geliştirme sırasında **açık** başlar) |
| İris / Geometri / **DeepWarp** | Düzeltme yöntemi — varsayılan **DeepWarp** |
| Güç | Düzeltme gücü 0–1 (varsayılan 0.70) |
| Gain | Piksel warp'ı için debug çarpanı. **DeepWarp modunda etkisizdir** (EXP-008) |

Üstteki durum göstergesi düzeltmenin aktif olup olmadığını ve değilse **sebebini**
gösterir (örn. "Kafa çok dönük (yaw 27°)").

## Kod imzalama

`CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`.
Kendi geliştirici hesabınla otomatik imzalanır.

App Sandbox açık, `com.apple.security.device.camera` entitlement'ı var.

⚠️ MVP 5'te Camera Extension eklendiğinde imzalama gereksinimleri değişecek
(Developer ID + notarization + system extension entitlement) →
[VIRTUAL_CAMERA.md](VIRTUAL_CAMERA.md#macos--camera-extension-cmioextension)

## Model yükleme sorunları

Uygulama başlarken konsola yazar:

```
[ONNXFaceLandmarker] ✅ Initialized successfully with model: ...
[DeepWarpModel] ✅ Loaded both eye models
```

`❌` görürsen model dosyası bundle'da değildir. Düzeltme çalışmıyorsa ilk bakılacak
yer burasıdır. Model yüklenemezse uygulama çökmez: landmark için Apple Vision'a,
düzeltme için geometrik warp'a düşer.

⚠️ Uygulama App Sandbox içinde çalıştığı için `/tmp` gibi yerlere yazamaz ve
`open` ile başlatıldığında `print` çıktısı terminale düşmez. Konsol çıktısını görmek
için Xcode'dan çalıştır (⌘R).

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
├── models/              # model kaynakları + dönüşüm çıktıları (git'e girmez)
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
