# PROJECT

## Amaç

EyesOn, video görüşmelerinde kullanıcının bakışını gerçek zamanlı olarak kameraya
yönlendiren bir masaüstü uygulamasıdır.

Problem şu: kamera ekranın üstünde, insanın baktığı yer ekranın ortası. Aradaki
5–10 derecelik açı yüzünden görüntülü görüşmede kimse birbirinin gözüne bakmıyor.
Karşı taraf bunu "ilgisiz" veya "başka şeye bakıyor" diye okuyor.

## Kullanıcı senaryosu

Kullanıcı Zoom, Google Meet, Microsoft Teams, Discord veya kamera seçebilen başka bir
uygulamada toplantıya katılır. Fiziksel olarak ekrana, toplantıdaki kişilere, notlarına
veya ekranın başka bölgelerine bakıyor olsa bile işlenmiş video çıkışında gözleri
mümkün olduğunca doğal şekilde kameraya bakıyor görünür.

```
Camera → EyesOn → corrected video → Virtual Camera → Zoom / Meet / Teams / Discord
```

Kullanıcı EyesOn'u açar, konferans uygulamasının kamera listesinden "EyesOn"u seçer,
ve unutur.

## Product vision

- **Kamera bağımsızlığı** — MacBook dahili kamera, USB webcam, harici capture card,
  Windows laptop kamerası, herhangi bir UVC uyumlu cihaz
- **Sistem çapında çalışma** — belirli bir konferans uygulamasına bağlı olmamak
- **Doğallık** — NVIDIA Broadcast "Eye Contact" seviyesine yaklaşmak. Fark edilen
  düzeltme, düzeltmemekten kötüdür
- **Gizlilik** — tüm işleme cihaz üzerinde; hiçbir kare cihazı terk etmez
- **GPU bağımsızlığı** — NVIDIA Broadcast RTX gerektirir; biz gerektirmemeliyiz

## Mevcut geliştirme aşaması

**MVP 0 tamamlandı** (dokümantasyon + AI hafıza altyapısı).
**MVP 1 başlamak üzere** (temel doğrulama + kamera I/O).

Uygulama şu an bir **yüz/göz tespiti demosudur**, ürün değildir. Kendi penceresinde
kamera görüntüsünü ve debug katmanlarını gösterir. Konferans uygulamalarına hiçbir şey
göndermez.

Tam MVP listesi: [ROADMAP.md](ROADMAP.md)

## Target Pipeline Status

Hedef pipeline'ın her aşamasının **repository'deki gerçek durumu**:

| # | Aşama | Durum | Nerede |
|---|---|---|---|
| 1 | Physical Camera | **Partial** | Varsayılan cihaz açılıyor; cihaz seçimi/enumeration yok |
| 2 | Camera Capture | **Implemented** | `CameraManager.swift` — AVFoundation, 720p, AsyncStream |
| 3 | Face Detection | **Implemented** | `VisionProcessor.swift` — Apple Vision |
| 4 | Face Tracking | **Partial** | `VNSequenceRequestHandler` kare arası izleme sağlıyor; ayrı bir tracker yok |
| 5 | Landmark Detection | **Implemented** | Apple Vision `VNDetectFaceLandmarksRequest`; iris yok, kaba pupil var |
| 6 | Head Pose | **Partial** | Vision'ın `yaw`/`pitch` değerleri yalnızca doğrulama kapısında kullanılıyor; bakış hesabına girmiyor. Roll hiç kullanılmıyor |
| 7 | Gaze Estimation | **Partial** | `GazeEstimator.swift` — pupil/göz-merkezi offset'i; 5 ayrık yön + ham offset. 3B geometri veya solvePnP yok |
| 8 | Eye Contact Correction | **Experimental** | `EyeCorrectionProcessor.swift` + `GaussianEyeWarp.metal`. **Varsayılan kapalı**, doğruluğu doğrulanmadı |
| 9 | Temporal Stabilization | **Partial** | `GazeSmoother` — 6 karelik mod filtresi, yalnızca ayrık yön etiketi için. EMA yok, davranış FSM'i yok, fade yok |
| 10 | Frame Reconstruction / Blending | **Partial** | Gaussian warp tüm kareye uygulanıyor; maskeli harmanlama yalnızca kullanılmayan CPU fallback'inde var |
| 11 | Virtual Camera | **Not Implemented** | Kod yok. Çıktı yalnızca kendi SwiftUI penceresine gidiyor |
| 12 | Zoom / Meet / Teams | **Not Implemented** | 11 olmadan mümkün değil |

Detaylar: [ARCHITECTURE.md](ARCHITECTURE.md) · [EYE_CONTACT.md](EYE_CONTACT.md) ·
[VIRTUAL_CAMERA.md](VIRTUAL_CAMERA.md)

## Mevcut özellikler

- Kamera izni akışı (`notDetermined` / `denied` / `authorized` durumları ve izin ekranı)
- Canlı kamera önizlemesi
- Gerçek zamanlı yüz tespiti ve göz landmark'ları
- Bakış yönü göstergesi (Merkez / Sol / Sağ / Yukarı / Aşağı)
- Debug katmanları: yüz kutusu, landmark noktaları, göz ROI'si, HUD (aç/kapa düğmeleriyle)
- Düzeltmenin güvenli olup olmadığına karar veren doğrulama kapısı (kafa açısı, göz
  açıklığı, yüz boyutu) ve red sebebinin ekranda gösterilmesi
- Deneysel göz düzeltmesi — arayüzden "⚡ Düzeltme" ile açılabiliyor, varsayılan kapalı

## Planlanan özellikler

MVP sırasına göre: cihaz seçimi → MediaPipe iris landmark'ları → davranış FSM'i +
temporal stabilizasyon → düzeltme kalitesi → **virtual camera** → paketleme/dağıtım →
öğrenilmiş warp modeli → Windows → iOS/iPadOS → Android.

Detay: [ROADMAP.md](ROADMAP.md)

## Kapsam dışı

- Arka plan bulanıklaştırma / değiştirme
- Ses işleme, gürültü engelleme
- Yüz güzelleştirme, makyaj, filtre
- **Bulut işleme** — mimari kısıt, tasarım seçeneği değil
- Çoklu yüz düzeltme — tek kullanıcı, kendi kamerası
- Kendi konferans uygulamamızı yazmak (mobil hariç; bkz. [PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md))

## Başarı ölçütü

1. **Doğallık** — düzeltme fark edilmemeli. "Ölü gözlü / bakışsız" görünmek en büyük
   başarısızlık modudur
2. **Gecikme** — uçtan uca ≤ 20 ms hedefi, 30 fps'te kare düşürmeden *(henüz ölçülmedi)*
3. **Görünmezlik** — kalibrasyon zorunlu olmamalı
4. **Dürüstlük** — kullanıcı gerçekten başka yere bakıyorsa düzeltme kendiliğinden
   çekilmeli. Sürekli zorla göz teması ürkütücüdür

4. madde bir konfor özelliği değil, doğallık iddiasının temelidir. Mekanizması:
[EYE_CONTACT.md](EYE_CONTACT.md#davranış-durum-makinesi-planlanan).
