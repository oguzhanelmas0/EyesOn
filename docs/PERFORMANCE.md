# PERFORMANCE

## ⚠️ Hiçbir ölçüm yapılmamıştır

Bu projede **benchmark altyapısı yoktur** ve uygulama henüz profillenmemiştir.
Aşağıdaki tablolardaki her hücre "Not measured yet"tir.

**Sayı uydurma.** Ölçtüğünde bu dosyayı güncelle ve hangi donanımda ölçtüğünü yaz.

## Ölçüm tablosu

| Platform | Resolution | FPS | Total Latency | Inference | CPU | GPU | Memory |
|---|---|---|---|---|---|---|---|
| macOS (Apple Silicon) | 1280×720 | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| macOS (Intel) | 1280×720 | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| Windows | — | Not implemented | — | — | — | — | — |
| iOS / iPadOS | — | Not implemented | — | — | — | — | — |
| Android | — | Not implemented | — | — | — | — | — |

## Latency budget (hedef, ölçüm değil)

30 fps → kare başına **33 ms tavan**. Hedef bütçe:

| Aşama | Hedef |
|---|---|
| Capture | ~1 ms |
| Preprocess (format dönüşümü, ölçekleme) | ~1 ms |
| Landmark inference | 8–12 ms |
| Gaze estimation + head pose | 1–2 ms |
| Behavior FSM + smoothing | < 0.5 ms |
| Warp — geometrik | 2–3 ms |
| Warp — öğrenilmiş model (48×64) | 3–5 ms |
| Blending | ~1 ms |
| Virtual camera output | ~0.5 ms |
| **Toplam hedef** | **~15–22 ms** |

⚠️ Bu rakamlar `reference/gaze-corrector` projesinin kendi README'sinde beyan ettiği
değerlerden türetilmiştir (Intel ve Apple Silicon Mac, MediaPipe + geometrik warp).
**Bizim kodumuzda doğrulanmamıştır.** Referans olarak kullan, iddia olarak değil.

Bütçenin yarısından fazlasını landmark çıkarımı yer. Optimizasyon gerekirse ilk
bakılacak yer orasıdır (örn. her karede tam tespit yerine, aradaki karelerde takip).

## Beklenen sıcak noktalar (mevcut kod, profillenmedi)

Kod okumasına dayalı tahmin sıralaması:

1. `VNDetectFaceLandmarksRequest` — her karede tam tespit
2. `CIContext.createCGImage` — GPU→CPU kopyası, her karede
3. `CIWarpKernel` — göz başına bir kez, **tüm kare genişliğinde** (bkz.
   [EYE_CONTACT.md](EYE_CONTACT.md#p2--warp-her-göz-için-tüm-kareye-uygulanıyor))
4. `NSImage` oluşturma + SwiftUI yeniden çizimi

Not: virtual camera'ya geçildiğinde 2 ve 4 tamamen ortadan kalkabilir — çıktı doğrudan
`CVPixelBuffer` olarak verilir. Bu tek başına anlamlı bir kazanç olabilir.

## Ölçüm nasıl yapılacak

**macOS — bugün mümkün olanlar:**

| Araç | Ne için |
|---|---|
| Xcode Instruments — Time Profiler | CPU sıcak noktaları |
| Xcode Instruments — Metal System Trace | GPU süresi, CIWarpKernel maliyeti |
| Xcode Instruments — Allocations | Bellek |
| `signposts` (`os_signpost`) | Aşama başına gerçek gecikme, uygulama içi |
| `CACurrentMediaTime()` farkı | Basit kare süresi ölçümü |

**Önerilen ilk adım (MVP 1):** boru hattının her aşamasına `os_signpost` ekle ve
Instruments'ta aşama başına dağılımı çıkar. Bu, tahmin listesini gerçek veriyle
değiştirir ve sonraki tüm optimizasyon kararlarının temeli olur.

**Regresyon karşılaştırması:** aynı kısa video dosyası her önemli değişiklikten sonra
işlenip FPS ve gecikme karşılaştırılmalı → [TESTING.md](TESTING.md#5-performance-tests)

## Ölçüm kaydı formatı

Ölçüm yaptığında `.ai/EXPERIMENTS.md`'ye şu bilgilerle kaydet:

```
Hardware:  (ör. MacBook Pro M3 Pro, 18 GB, macOS 26.3)
Input:     (ör. 1280×720 @ 30fps, dahili kamera / test videosu adı)
Build:     (Debug / Release — Release olmayan ölçüm yanıltıcıdır)
FPS:
Per-frame latency (p50 / p95):
Aşama dağılımı:
CPU % / GPU % / Memory:
```

⚠️ **Debug build'de ölçüm yapma.** Swift ve Metal'de Debug/Release farkı çok büyüktür;
Debug rakamı yanıltıcıdır ve yanlış optimizasyon kararlarına yol açar.
