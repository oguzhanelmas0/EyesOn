# TESTING

## ⚠️ Mevcut durum: hiçbir test altyapısı yok

Repository'de bugün:

- ❌ Test target'ı yok (`EyesOn.xcodeproj` tek uygulama target'ı içerir)
- ❌ XCTest / Swift Testing yok
- ❌ CI yok
- ❌ Benchmark betiği yok
- ❌ Test video varlıkları yok
- ❌ `tests/` klasörü yok

`reference/deepwarp-cam` içindeki `bin_test_*.py` dosyaları **bizim testlerimiz
değildir** — referans projenin manuel deneme betikleridir ve derlenmezler.

**Bugün yapılabilecek tek doğrulama:** Xcode'da derleyip çalıştırmak ve gözle kontrol
etmek. Bir agent "test ettim" demeden önce ne yaptığını açıkça söylemelidir:
*"derlendi ama çalıştırılmadı"*, *"çalıştırıldı, gözle kontrol edildi"* gibi.

---

## Önerilen test seviyeleri

Aşağıdakiler **plandır, mevcut değildir.** MVP'ler ilerledikçe kurulacaktır.

### 1. Unit Tests

Saf fonksiyonlar için — bunlar kameradan bağımsızdır ve hızlı çalışır:

| Ne | Neden test edilebilir |
|---|---|
| `LandmarkValidator` eşikleri | Sahte `VNFaceObservation` ile sınır değerleri |
| `VisionCoordinateMapper` dönüşümleri | Bilinen girdi → bilinen çıktı; **P3 riskini yakalar** |
| Behavior FSM durum geçişleri | Zamana bağlı ama enjekte edilebilir saat ile deterministik |
| EMA filtreleri | Basit sayısal doğrulama |
| Bakış açısı matematiği | Bilinen landmark → beklenen açı |

**Kurulacağı yer:** MVP 1 — Xcode'a bir unit test target'ı eklenmesi.

**En yüksek öncelik:** koordinat dönüşümleri. `EyeCorrectionProcessor` ve
`VisionCoordinateMapper` aynı matematiğin iki kopyasını içeriyor (P3); bir test bu ikisinin
aynı sonucu verdiğini doğrulayabilir ve sessiz ayrışmayı engeller.

### 2. Video File Tests

Kamera olmadan, kaydedilmiş video üzerinden tam boru hattı.

- `AVAssetReader` ile kareleri okuyup aynı işleme hattından geçirmek
- Deterministik: aynı video → aynı çıktı
- CI'da çalışabilir

**Bu, en yüksek getirili test tipidir** ve regresyon karşılaştırmasının temelidir.

### 3. Webcam Tests

Manuel, gözle. Kontrol listesi:

- İzin akışı (ilk açılış, reddedilmiş durum)
- Kamera bağlı değilken davranış
- Kamera çalışırken çıkarma/takma
- Farklı kameralar (dahili, USB webcam, Continuity Camera)
- Farklı mesafeler, ışık koşulları, gözlük

### 4. Visual Quality Tests

Otomatikleştirmesi zor, ama sistematik yapılabilir. Her önemli değişiklikten sonra
aynı test videosunda şu listeye bakılır:

uncanny eye appearance · iris/pupil deformation · eyelid artifacts · identity drift ·
face geometry deformation · texture inconsistency · lighting mismatch · eye color changes ·
asymmetrical eyes · blink corruption

**Yöntem:** öncesi/sonrası kare çiftlerini yan yana kaydet, `.ai/EXPERIMENTS.md`'ye
gözlemleri yaz.

### 5. Performance Tests

Bkz. [PERFORMANCE.md](PERFORMANCE.md#ölçüm-nasıl-yapılacak).

Regresyon yaklaşımı: **aynı kısa video her model/algoritma değişiminde çalıştırılır** ve
FPS, gecikme dağılımı (p50/p95), CPU/GPU kullanımı karşılaştırılır. Ölçüm **Release
build'de** yapılır.

### 6. Virtual Camera Tests

MVP 5'ten sonra anlamlı:

- Extension kurulumu ve kaldırılması
- Cihazın sistem kamera listesinde görünmesi
- Uygulama kapalıyken davranış
- Format/çözünürlük/FPS uyumu
- Uzun süreli kararlılık (bellek sızıntısı, kare düşmesi)

### 7. Conferencing App Tests

Her uygulama sanal kameraları farklı listeler ve farklı formatlar bekler. Gerçek test
şart:

| Uygulama | Test edildi |
|---|---|
| Zoom | ❌ |
| Google Meet (Chrome/Safari) | ❌ |
| Microsoft Teams | ❌ |
| Discord | ❌ |
| FaceTime | ❌ |
| QuickTime Player (en basit doğrulama) | ❌ |

---

## Regression video yaklaşımı

Eye-contact correction'da **tek frame yeterli değildir** — video boyunca stabil olmalıdır.
Bu yüzden önerilen çekirdek yöntem:

```
Sabit test videosu  →  boru hattı  →  çıktı videosu + metrikler
                                        │
                        önceki sürümün çıktısıyla karşılaştır
                                        │
                    FPS · latency · landmark stability · gaze jitter · görsel fark
```

**Test videosu seti (önerilen, henüz yok):**

| Video | İçerik | Test ettiği |
|---|---|---|
| `baseline_center.mov` | Kameraya sabit bakış | Düzeltme gereksizken müdahale etmiyor mu |
| `reading_notes.mov` | Aşağıya bakıp geri dönme | FSM disengage/re-engage |
| `head_turn.mov` | Yavaş kafa çevirme | Yaw eşiği, geçiş yumuşaklığı |
| `blinking.mov` | Normal göz kırpma | Blink corruption |
| `glasses.mov` | Gözlüklü kullanıcı | Yansıma dayanıklılığı |
| `low_light.mov` | Karanlık oda | Tespit kalitesi |
| `fast_motion.mov` | Hızlı hareket | Landmark gecikmesi, jitter |

**Yeri:** `tests/assets/` (henüz yok). Video dosyaları **git'e girmemeli** — boyut
sebebiyle. `models/` gibi bir indirme/README yaklaşımı veya Git LFS değerlendirilmeli.

⚠️ Gizlilik: test videoları gerçek insan yüzü içerir. Repository public olduğu için
bunlar **kesinlikle commit edilmemelidir.**

---

## Ne zaman ne kurulacak

| MVP | Eklenecek test altyapısı |
|---|---|
| MVP 1 | Unit test target'ı; koordinat dönüşümü testleri; `os_signpost` ile ölçüm |
| MVP 3 | FSM ve EMA unit testleri; ilk test videoları |
| MVP 4 | Video file test hattı; görsel regresyon karşılaştırması |
| MVP 5 | Virtual camera smoke test; konferans uygulaması matrisi |
| MVP 7 | Model export doğrulama (aynı girdi → hedefler arası sayısal fark) |
