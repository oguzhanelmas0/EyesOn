# EYE_CONTACT

Projenin kritik teknik dokümanı. İki bölüm: **mevcut implementasyon** ve **planlanan
yöntem** (referans projelerden damıtılmış). `reference/` klasörü silinse bile algoritma
buradan yeniden inşa edilebilmelidir.

---

# BÖLÜM 1 — Mevcut implementasyon (macOS, Apple Vision)

## 1.1 Face detection + landmarks

`VisionProcessor.swift` — `VNSequenceRequestHandler` + `VNDetectFaceLandmarksRequest`.
Sequence handler kullanılması kare arası izleme sağlar (ayrı bir tracker yoktur).

Apple Vision'ın verdiği landmark bölgeleri arasında kullandıklarımız: `leftEye`,
`rightEye`, `leftPupil`, `rightPupil`. Ayrıca `VNFaceObservation.yaw` ve `.pitch`
doğrudan Vision'dan gelir (radyan).

⚠️ **Kritik sınırlama:** `leftPupil` / `rightPupil` göz başına **tek ve kaba** bir nokta
verir. MediaPipe göz başına 5 iris noktası verir. Bakış tahmini doğrudan bu noktaya
bağlı olduğu için hassasiyet burada tavanlanıyor → ADR-001.

## 1.2 Validation gate

`Vision/LandmarkValidator.swift`. **Sırayla** kontrol edilir, ilk başarısızlıkta durur
ve red sebebi UI'da gösterilir. Herhangi biri başarısızsa düzeltme yapılmaz, kare
olduğu gibi geçer.

| Kontrol | Eşik | Sebep |
|---|---|---|
| Yüz kutusu genişliği | ≥ 0.10 (kare genişliğine göre) | Uzaktaki yüzde landmark güvenilmez |
| Göz landmark sayısı | ≥ 6 / göz | Eksik tespit |
| Eye Aspect Ratio (EAR) | ≥ 0.11 | Göz kapalı/kısık → warp bozar |
| Kafa yaw | ≤ 22° | Profil yüzde göz geometrisi çöker |
| Kafa pitch | ≤ 22° | Aynı |
| Gözler arası mesafe | ≥ 0.10 (yüz kutusuna göre) | Saçma tespit filtresi |

**EAR** = göz landmark'larının sınırlayıcı kutu yüksekliği / genişliği.
Açık göz ≈ 0.25–0.35, kapalı/kısık < 0.12.

Bu kapı iyi tasarlanmış ve korunmalıdır. **Düzeltmemek her zaman geçerli bir çıktıdır.**

## 1.3 Gaze estimation

`GazeEstimator.swift`. Göz başına:

```
göz_centroid = göz landmark noktalarının ortalaması
göz_genişliği = landmark x aralığı
offset = (pupil_ortalaması − göz_centroid) / göz_genişliği     ← x ve y aynı böleni kullanır
```

İki gözün offset'i ortalanır. Ayrık sınıflandırma:

| Sabit | Değer |
|---|---|
| `xThreshold` | 0.10 |
| `yThreshold` | 0.08 |
| `minEyeOpen` | 0.35 |

Dikey ekseni yatay eksene göre önceliklendirir (`absY >= absX` ise dikey kazanır).
Yukarı yönü ek olarak göz açıklığı kontrolünden geçer — kısık gözde "yukarı" yerine
"merkez" döner.

⚠️ Head pose (yaw/pitch) **bakış hesabına girmiyor**, yalnızca doğrulama kapısında
kullanılıyor. Kafa dönükken pupil offset'i yanıltıcıdır; bu düzeltilmemiş bir eksiktir.

⚠️ `offset.y` de `göz_genişliği`ne bölünüyor (yüksekliğe değil). Kasıtlı olabilir
(göz genişliği daha stabil bir ölçek referansıdır) ama dikey ve yatay eşiklerin farklı
olması bunu telafi etmeye çalışıyor gibi görünüyor. **TODO: verify.**

## 1.4 Temporal smoothing

`GazeSmoother` — son 6 karenin **mod'u** (en sık görülen yön). Ayrık etiketler için
makul, ancak:

- Yalnızca UI etiketi için uygulanıyor; düzeltme ham `rawOffset`'i kullanıyor
- Sürekli değerler için mod filtresi uygun değil — EMA gerekir
- Fade / geçiş yok: düzeltme eşiği geçince **birden** açılıp kapanıyor

## 1.5 Eye correction

`EyeCorrectionProcessor.swift` + `GaussianEyeWarp.metal`.

Koşullar: `correctionEnabled && validation.isSafe && direction != .center`.
**`correctionEnabled` varsayılan `false`** — arayüzdeki "⚡ Düzeltme" düğmesiyle açılıyor.

Metal `CIWarpKernel` — her çıktı pikseli için kaynak koordinatı döndürür:

```
ağırlık = exp(−‖p − göz_merkezi‖² / (2σ²)) × güç
kaynak  = p + (pupil_merkezi − göz_merkezi) × ağırlık
```

| Sabit | Değer |
|---|---|
| `correctionStrength` | 0.90 |
| `maxPixelShift` | 20.0 px |
| `sigmaFraction` | 0.45 (σ = göz genişliği × 0.45) |
| ROI genişletme | σ × 5 |

Fikir doğru: göz merkezinde ağırlık ≈ güç → pupil'den örneklenir, iris ortaya gelir.
Köşelerde ağırlık ≈ 0 → göz dış hatları sabit kalır. Aradaki Gaussian sönümleme gerçek
bir göz dönüşünü taklit eder.

Metal kütüphanesi yüklenemezse CPU fallback'i var (basit piksel kaydırma +
`CIBlendWithMask`), ancak yorumunun kendisi "hayalet iris bırakır" diyor.

---

## Bilinen kod problemleri

Aşağıdakiler **kodda doğrulanmış** gözlemlerdir; tahmin değildir.

### P1 — `maxPixelShift` Metal yolunda hiç uygulanmıyor
`EyeCorrectionProcessor.warpEye` içinde `dispX`/`dispY` hesaplanıp 20 piksele clamp
ediliyor, ama Metal yoluna **bu clamp'lenmiş değerler gönderilmiyor** — kernel'e ham
`pupilCenter` ve `eyeCenter` geçiliyor ve fark GPU'da yeniden hesaplanıyor. Sonuç:
20 piksel tavanı yalnızca hiç kullanılmayan CPU fallback'inde geçerli. Yüz kameraya
yakınken deplasman sınırsız büyüyebilir. **Gerçek bug.**

### P2 — Warp her göz için tüm kareye uygulanıyor
`correct()` sol ve sağ göz için `warpEye`'ı ayrı ayrı çağırıyor; her çağrı
`image.extent` genişliğinde bir `CIWarpKernel` işlemi kuruyor. `roiCallback` örnekleme
alanını daraltıyor ama iki tam kare geçişi yine de gereksiz. Göz ROI'sine kırpıp geri
kompozit etmek çok daha ucuz.

### P3 — Koordinat matematiği iki yerde
`EyeCorrectionProcessor` kendi private dönüşüm yardımcılarını kullanıyor
(`eyeCentroid`, `pixelRect`, `pupilPixelCenter`) — `VisionCoordinateMapper` varken.
Aynı matematiğin iki kopyası, sessizce ayrışma riski.

### P4 — Açık/kapalı titremesi
Düzeltme yalnızca `direction != .center` iken devrede. Ayrık bir eşik; kullanıcı eşiğin
kenarında dururken düzeltme kare kare açılıp kapanır. Çözüm: davranış FSM'i + fade.

### P5 — Head pose bakış hesabına girmiyor
Yaw/pitch yalnızca kapı olarak kullanılıyor. Kafa 15° dönükken pupil offset'i farklı
yorumlanmalı; şu an yorumlanmıyor.

### P6 — Aynalama ve koordinat ekseni doğrulanmadı
Ön kamera aynalaması ayarlanmamış, Vision orientation `.up`. "Sol"/"Sağ" etiketlerinin
gerçekten doğru yönü gösterip göstermediği **gözle doğrulanmadı**. Düzeltme yanlış yöne
gidiyorsa ilk bakılacak yer burasıdır — ve bu, ADR-001'in çözmeyeceği bir problemdir.

---

# BÖLÜM 2 — Planlanan yöntem

Kaynak: `reference/gaze-corrector` (geometrik) ve `reference/deepwarp-cam` (öğrenilmiş).
Sabitler o projelerden alınmış, deneyle kalibre edilmiş değerlerdir. Değiştirirken
sebebini buraya yaz.

## 2.1 MediaPipe landmark indeksleri

`refine_landmarks = true` → **478 nokta**. Normalize (x, y, z); piksel uzayına
`x·genişlik`, `y·yükseklik`, `z·genişlik`.

```
İRİS (refine_landmarks ile gelir — asıl değer burada)
  Sol  iris merkezi : 468        Sol  iris çevresi : 469, 470, 471, 472
  Sağ  iris merkezi : 473        Sağ  iris çevresi : 474, 475, 476, 477

GÖZ KONTURU (16 nokta / göz)
  Sağ : 33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246
  Sol : 362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398

KAFA POZU (solvePnP için 6 nokta)
  1 (burun ucu), 33 (sağ göz dış köşe), 263 (sol göz dış köşe),
  61 (sağ ağız köşe), 291 (sol ağız köşe), 199 (çene)
```

"Sol" ve "sağ" **izleyicinin perspektifindedir** (görüntüdeki sol/sağ), kişinin kendi
sol/sağı değil. En sık yapılan hata burada — kodda yorumla belirt.

## 2.2 Head pose (solvePnP)

3B genel yüz modeli noktaları (mm):

```
(   0.0,    0.0,    0.0)   burun ucu        ← landmark 1
(-225.0,  170.0, -135.0)   sağ göz dış köşe ← landmark 33
( 225.0,  170.0, -135.0)   sol göz dış köşe ← landmark 263
(-150.0, -150.0, -125.0)   sağ ağız köşe    ← landmark 61
( 150.0, -150.0, -125.0)   sol ağız köşe    ← landmark 291
(   0.0, -330.0,  -65.0)   çene             ← landmark 199
```

Kamera matrisi yaklaşımı: `focal_length = kare_genişliği`, merkez = kare merkezi,
distorsiyon sıfır. Kaba ama yaw/pitch/roll için yeterli. Rodrigues → Euler açıları.

## 2.3 Bakış tahmini — Yöntem A (iris offset, model gerektirmez)

Kaynak: `reference/gaze-corrector/gaze_estimator.py`

```
göz_merkezi   = göz konturu 16 noktasının ortalaması
göz_genişliği = kontur x aralığı ;  göz_yüksekliği = kontur y aralığı
iris_offset   = (iris_merkezi − göz_merkezi) / (göz_genişliği, göz_yüksekliği)   → ~[-1, 1]

bakış_açısı ≈ ‖ortalama |iris_offset|‖ × 30      (derece, ampirik)

düzeltme_x = −iris_offset.x × göz_genişliği
düzeltme_y = −iris_offset.y × göz_yüksekliği × DIKEY_SÖNÜM
```

**`DIKEY_SÖNÜM = 0.5`** — dikey düzeltme kasten yarıya indirilir. Ekrana bakan insanın
gözü zaten doğal olarak biraz aşağıdadır; bunu tam düzeltmek yapay görünür. Bu, tüm
sistemdeki en incelikli sabittir, keyfi değildir.

Mevcut Swift kodundan farkı: iris merkezi 5 noktadan gelir (tek kaba nokta yerine),
x ve y **kendi boyutlarına** normalize edilir, ve dikey sönüm vardır.

## 2.4 Bakış tahmini — Yöntem B (3B geometri, kalibrasyon ister)

Kaynak: `reference/deepwarp-cam/model_managers/gaze_corrector_v1.py`
Makale: Hsu, Wang, Lei, Chen — *"Look at Me! Correcting Eye Gaze in Live Video
Communication"*, ACM TOMM 15(2), 2019.

Gözün 3B konumunu, gözler arası mesafenin bilinen fiziksel uzunluğundan çıkarır:

```
ipd_piksel = ‖sol_göz_merkezi − sağ_göz_merkezi‖

göz_z = −(odak_uzaklığı × IPD) / ipd_piksel                    (cm, kameraya göre)

göz_x = −|göz_z| × (sol_x + sağ_x − kare_genişliği)  / (2 × odak_uzaklığı) + kamera_offset_x
göz_y =  |göz_z| × (sol_y + sağ_y − kare_yüksekliği) / (2 × odak_uzaklığı) + kamera_offset_y

hedef = (0, 0, 0)                                    ← kamera merceği

açı_dikey = atan((hedef_y − göz_y) / (hedef_z − göz_z))
          + atan((göz_y − kamera_offset_y) / (kamera_offset_z − göz_z))
açı_yatay = atan((hedef_x − göz_x) / (hedef_z − göz_z))
          + atan((göz_x − kamera_offset_x) / (kamera_offset_z − göz_z))
```

| Parametre | Varsayılan | Anlamı |
|---|---|---|
| `odak_uzaklığı` | 650 px | Kameranın piksel cinsinden odak uzaklığı |
| `IPD` | 6.3 cm | Gözbebekleri arası mesafe (insan ortalaması) |
| `kamera_offset` | (0, −21, −1) cm | Kameranın ekran merkezine göre konumu |

`kamera_offset_y = −21 cm` → "kamera ekranın 21 cm üstünde", tipik bir dizüstü.
Bu üç değer kullanıcı başına kalibre edilebilir olmalı ama **kalibrasyon zorunlu
olmamalıdır.**

Odak uzaklığı kalibrasyonu: kullanıcı yüzünü kameradan ~50 cm uzağa koyar, IPD 6.3 cm
varsayılır, `odak_uzaklığı = ipd_piksel × 50 / 6.3`.

## 2.5 Davranış durum makinesi (planlanan)

Kaynak: `reference/gaze-corrector/behavior_fsm.py`

**Ürünün doğal hissetmesini sağlayan tek en önemli parça budur.** Kullanıcı gerçekten
notlarına bakıyorsa düzeltme çekilmeli; geri döndüğünde yumuşakça geri gelmeli.
Histerezis (açma ve kapama eşiklerinin farklı olması) titremeyi engeller.

```
     bakış yakın              bakış uzak
   ┌──────────┐            ┌──────────────┐
   │ ENGAGED  │───────────►│ DISENGAGING  │──── 0.4 sn ────► ┌────────────┐
   │ blend=1  │◄───────────│  (sönüyor)   │                  │ DISENGAGED │
   └──────────┘            └──────────────┘                  │  blend=0   │
         ▲                                                   └─────┬──────┘
         │                  ┌──────────────┐                       │
         └──── 0.2 sn ──────│ RE_ENGAGING  │◄──── bakış yakın ─────┘
                            │  (doğuyor)   │
                            └──────────────┘
```

| Sabit | Değer | Anlamı |
|---|---|---|
| `ENGAGE_THRESHOLD` | 15° | Bakış açısı bunun altına inerse yeniden devreye gir |
| `DISENGAGE_THRESHOLD` | 25° | Bakış açısı bunu aşarsa çekilmeye başla |
| `HEAD_YAW_THRESHOLD` | 20° | Kafa bu kadar dönerse **anında** çekil |
| `HEAD_PITCH_THRESHOLD` | 15° | Kafa bu kadar eğilirse **anında** çekil |
| `DISENGAGE_DURATION` | 0.4 sn | Sönme süresi |
| `RE_ENGAGE_DURATION` | 0.2 sn | Doğma süresi |

15°–25° arası histerezis bandıdır; kullanıcı bu bantta gezinirken durum değişmez.
Sönmenin doğmadan iki kat yavaş olması kasıtlıdır: aniden kaybolan düzeltme göze çarpar,
aniden gelen çarpmaz.

FSM tek bir sayı döndürür: **`blend ∈ [0, 1]`**. Warp'ın etkisi bununla çarpılır.

## 2.6 Temporal smoothing (planlanan)

Kaynak: `reference/gaze-corrector/smoothing.py` — EMA: `değer ← α × yeni + (1−α) × değer`

| Ne | α | Sebep |
|---|---|---|
| Landmark konumları | 0.6 | Yanıt verici kalmalı; fazla yumuşatma gecikme hissi yaratır |
| Düzeltme blend faktörü | 0.3 | Yavaş ve fark edilmez geçiş |

## 2.7 Geometrik warp (MVP 4)

Kaynak: `reference/gaze-corrector/gaze_corrector.py`

1. **Göz ROI'sini kırp** — kontur sınırlayıcı kutusu + dolgu (yatay %30, dikey %50).
   Dikey dolgunun büyük olması kaş ve alt göz kapağı dokusunun warp'a dahil olması içindir.
2. **Warp uygula:**
   - *3 noktalı affine* (hızlı): iki göz köşesi sabit çapa, iris merkezi
     `düzeltme × güç` kadar kaydırılır
   - *Parçalı affine* (kaliteli, yavaş): kontur noktaları + ROI köşeleri sabit, iris
     noktaları kaydırılır; Delaunay üçgenlemesi ile üçgen üçgen warp
3. **Geri harmanla** — göz konturunun convex hull'undan maske, Gaussian bulanıklık
   (kernel 15) ile feather, `maske × blend` ile orijinal kareye harmanla

`güç` varsayılanı **0.7**. Tam düzeltme (1.0) çoğu yüzde yapay görünür.

Mevcut Metal Gaussian warp'ı ile karşılaştırılmalı — Gaussian yaklaşımı GPU'da daha ucuz
ve daha yumuşak, parçalı affine daha kontrollü. MVP 4'te ikisi de denenip
`.ai/EXPERIMENTS.md`'ye kaydedilecek.

## 2.8 Öğrenilmiş warp — DeepWarp (MVP 7)

Kaynak: `reference/deepwarp-cam/tf_models/gaze_corrector_v1/gaze_warp_model.py`

Girdi başına **48×64** göz görüntüsü, üç girdi:

| Girdi | Şekil | İçerik |
|---|---|---|
| Göz görüntüsü | 48×64×3 | [0,1] normalize RGB |
| Anchor map | 48×64×12 | 6 göz landmark'ının her biri için (Δx, Δy) mesafe haritası |
| Açı | 2 | (dikey, yatay) düzeltme açısı, **derece** |

Anchor map: her landmark için, o landmark'a göre her pikselin x ve y mesafesini içeren
iki kanal. 6 × 2 = 12. Ağa "göz nerede, nasıl şekilli" bilgisini uzamsal olarak verir.

```
açı (2) ──► MLP (16→16→16) ──► uzamsal haritaya yay (48×64×16)
                                        │
görüntü (3) + anchor (12) ──────────────┴──► birleştir (48×64×31)
                                                    │
                              ¼ çözünürlüğe indir ──► COARSE: 32,64,64,32,16 ──► tanh
                                                    │      (yoğun bağlantılı CNN)
                                    tam çözünürlüğe çıkar + 2×2 ortalama havuz
                                                    │
                              orijinal girdi ile birleştir ──► FINE: 32,64,32,16,4
                                                    │
                                        ┌───────────┴───────────┐
                                    flow (2)                 lcm_in (2)
                                        │                        │
                                      tanh                   LCM: 8,8,2
                                        │                        │
                            spatial transformer            ışık ağırlıkları
                            (bilinear örnekleme)                 │
                                        └───────────┬────────────┘
                                                    ▼
                                  çıktı = warp × w_görüntü + beyaz × w_palet
```

Çekirdek boyutları: coarse ve fine `[5,5],[3,3],[3,3],[3,3],[1,1]`; LCM `[3,3],[3,3],[1,1]`.
**Sol ve sağ göz için ayrı ağırlıklar.**

Neden önemli: geometrik warp iris'i *kaydırır* ve arkasındaki göz akını esnetir; DeepWarp
bir **akış alanı** öğrenir ve üstüne ışık düzeltmesi uygular — gerçek bir göz dönüşünün
nasıl göründüğünü öğrenmiştir. Kalite farkı burada.

Ağ çok küçüktür (en geniş katman 64 kanal, 48×64 girdi) — telefonda bile gerçek zamanlı
çalışır. ONNX'e çevrilip CoreML / TFLite / ONNX Runtime ile beş platformda kullanılabilir.

⚠️ **Ağırlıklar elimizde yok.** `reference/deepwarp-cam` yalnızca mimariyi içerir.
MVP 7'nin ilk işi ağırlıkları bulmak ya da eğitmektir.

---

# Known Failure Modes

⚠️ **Aşağıdakiler henüz gözlemlenmemiştir** — uygulama bu oturumda çalıştırılmadı.
Bunlar bu problem sınıfının bilinen zorluklarıdır ve MVP 1'de sistematik olarak test
edilecektir. Gözlemlendiklerinde bu tablo gerçek bulgularla güncellenmelidir.

| Durum | Beklenen sorun | Mevcut savunma |
|---|---|---|
| Büyük yaw (profil) | Göz geometrisi çöker, warp bozar | ✅ Validator yaw > 22° reddediyor |
| Büyük pitch | Aynı | ✅ Validator pitch > 22° reddediyor |
| Gözlük | Yansıma, çerçeve landmark'ı bozar | ❌ Yok |
| Gözlük yansıması | Iris tespiti kayar | ❌ Yok |
| Kapalı göz / kırpma | Warp göz kapağını deforme eder | ✅ EAR < 0.11 reddediyor |
| Hızlı kafa hareketi | Landmark gecikmesi → yanlış yerde warp | ⚠️ Kısmi (mod filtresi) |
| Motion blur | Landmark güvenilmez | ❌ Yok |
| Düşük ışık | Tespit kalitesi düşer | ❌ Yok |
| Çoklu yüz | Hangi yüz düzeltilecek belirsiz | ⚠️ `observations.first` alınıyor — keyfi |
| Kısmi kapanma (el, mikrofon) | Eksik landmark | ✅ Landmark sayısı kontrolü |
| Yüz çok uzakta | Landmark hassasiyeti yetersiz | ✅ Yüz genişliği < %10 reddediyor |
| Yüz çok yakında | Deplasman aşırı büyür | ⚠️ `maxPixelShift` var ama **etkisiz** (P1) |
| Koyu ten / düşük kontrast | Iris/sklera ayrımı zorlaşır | ❌ Yok — test edilmeli |

**Test edilmemiş ama kritik:** dış aydınlatma değişimi sırasında flicker, ve iki gözün
asimetrik düzeltilmesi (her göz kendi offset'ini kullanırsa şaşılık görüntüsü oluşabilir —
mevcut kod iki gözün **ortalamasını** kullanıyor, bu doğru karar).
