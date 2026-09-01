# EyesOn

Görüntülü görüşmelerde **göz temasını düzelten** bir uygulama. Kullanıcı ekrana,
notlarına veya başka bir yere bakıyor olsa da karşı tarafa kameraya bakıyormuş gibi
görünür.

```
Camera → EyesOn → corrected video → Virtual Camera → Zoom / Meet / Teams / Discord
```

Hedef platformlar: macOS, Windows, iOS, iPadOS, Android.
Aktif geliştirme: **macOS**.

## Durum

Uygulama şu an bir **yüz/göz tespiti demosudur**, ürün değildir. Kamera yakalama ve
landmark tespiti çalışıyor; göz düzeltmesi deneysel ve varsayılan olarak kapalı;
sanal kamera henüz yazılmadı.

Aşama aşama gerçek durum: [docs/PROJECT.md](docs/PROJECT.md#target-pipeline-status)

## Başlangıç

```bash
open apps/macos/EyesOn.xcodeproj
```

Gereksinimler ve derleme detayı: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)

## Dokümantasyon

**Bir AI aracıyla (Claude / Codex / Gemini) çalışıyorsan önce [AGENTS.md](AGENTS.md)
oku.**

| Dosya | İçerik |
|---|---|
| [AGENTS.md](AGENTS.md) | Ortak çalışma kuralları, devir teslim protokolü |
| [.ai/CURRENT_TASK.md](.ai/CURRENT_TASK.md) | Aktif görev, nerede kalındı |
| [.ai/DECISIONS.md](.ai/DECISIONS.md) | Mimari kararlar (ADR) |
| [.ai/EXPERIMENTS.md](.ai/EXPERIMENTS.md) | Denenmiş yöntemler, başarısızlar dahil |
| [.ai/WORKLOG.md](.ai/WORKLOG.md) | Tamamlanmış işler |
| [docs/PROJECT.md](docs/PROJECT.md) | Ürün tanımı, kapsam, pipeline durumu |
| [docs/ROADMAP.md](docs/ROADMAP.md) | MVP planı |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Sistem mimarisi, modüller |
| [docs/VIDEO_PIPELINE.md](docs/VIDEO_PIPELINE.md) | Kare yaşam döngüsü, threading |
| [docs/EYE_CONTACT.md](docs/EYE_CONTACT.md) | **Kritik teknik doküman** — algoritma |
| [docs/CAMERA_IO.md](docs/CAMERA_IO.md) | Kamera enumeration, seçim, uyumluluk |
| [docs/VIRTUAL_CAMERA.md](docs/VIRTUAL_CAMERA.md) | Sanal kamera — henüz yazılmadı |
| [docs/MODEL_PIPELINE.md](docs/MODEL_PIPELINE.md) | ML modelleri ve export zinciri |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Benchmark — henüz ölçülmedi |
| [docs/PLATFORM_SUPPORT.md](docs/PLATFORM_SUPPORT.md) | Platform matrisi ve kısıtlar |
| [docs/TESTING.md](docs/TESTING.md) | Test stratejisi — altyapı henüz yok |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Kurulum, derleme, çalıştırma |
| [docs/REFERENCE_PROJECTS.md](docs/REFERENCE_PROJECTS.md) | `reference/` altında ne var |

## Gizlilik

Tüm görüntü işleme cihaz üzerinde, lokal yapılır. Kamera karesi hiçbir koşulda harici
bir servise gönderilmez.
