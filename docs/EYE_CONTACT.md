# EYE_CONTACT

Projenin kritik teknik dokümanı. İki bölüm: **mevcut implementasyon** ve **planlanan
yöntem** (referans projelerden damıtılmış). `reference/` klasörü silinse bile algoritma
buradan yeniden inşa edilebilmelidir.

---

> **2026-09-01 (2. güncelleme):** Artık **her iki referans yaklaşımı da** implement
> edilmiş durumda. MediaPipe landmark tespiti ve DeepWarp göz düzeltme modeli ONNX
> Runtime üzerinden çalışıyor. Bölüm 1 gerçek implementasyonu, Bölüm 2 algoritmaların
> tam tanımını (tek doğruluk kaynağı) anlatır.
>
> **Düzeltme yöntemi arayüzden seçilebilir:** `İris` · `Geometri` · `DeepWarp` (varsayılan).

# BÖLÜM 1 — Mevcut implementasyon (macOS, Apple Vision)

## 1.1 Face detection + landmarks ✅ MediaPipe

**Birincil:** `Vision/ONNXFaceLandmarker.swift` — MediaPipe Face Landmarker,
**478 3B nokta**, iris dahil (468–477), ONNX Runtime ile.
`Core/MediaPipeFaceAdapter.swift` sonucu kaynak-bağımsız `FaceGeometry`'ye çevirir.

Canlı doğrulandı: iris çemberleri göz bebeklerine milimetrik oturuyor; harici kamera
(Continuity Camera) ile de çalışıyor.

**Yedek:** Apple Vision (`VisionProcessor.swift` + `Core/VisionFaceAdapter.swift`).
⚠️ Vision'ın `leftPupil`/`rightPupil`'i göz başına tek ve kaba bir nokta verir —
canlı ölçümde göz merkezinden yalnızca 2–3 piksel sapıyordu (EXP-001). Bu yüzden
yedek yoldur, birincil değil.

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

## 1.3 Gaze estimation ✅ — iki yöntem

Artık **iki** tahmin yöntemi de implement edilmiş durumda ve arayüzden seçilebiliyor:

| Yöntem | Dosya | İris gerektirir mi | Bugün kullanışlı mı |
|---|---|---|---|
| **A — İris offset** | `Core/IrisGazeEstimator.swift` | ✅ Evet | ⚠️ Vision'ın pupil'i zayıf olduğu için sinyal küçük |
| **B — 3B geometri** | `Core/GazeGeometry3D.swift` | ❌ Hayır | ✅ **Evet** — gözler arası mesafeden çalışıyor |

Varsayılan **B**'dir. Sebebi ekranda ölçüldü: Vision'ın pupil noktası göz merkezinden
2–3 piksel ayrılıyor (`rawOff ≈ 0.04`), yani Yöntem A'nın girdisi neredeyse sıfır.
Yöntem B iris'e hiç bakmaz; gözün 3B konumunu gözler arası piksel mesafesinden çıkarır.
Detay: [2.4](#24-bakış-tahmini--yöntem-b-3b-geometri-kalibrasyon-ister).

### Eski (Vision'a bağlı) yöntem — kaldırıldı

`GazeEstimator.swift` artık yalnızca ekrandaki yön göstergesi için sınıflandırma yapıyor.
Ölçüm `Core/` altına, kaynak-bağımsız `FaceGeometry` üzerine taşındı. Eski hesap
şöyleydi (referans olarak):

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

## 1.4 Temporal smoothing ✅

`Core/EMAFilter.swift` — `FaceGeometrySmoother` tüm landmark noktalarını, iris
merkezlerini ve kafa açılarını EMA ile yumuşatıyor (α = 0.6), **bakış tahmininden önce**,
böylece bütün alt hesaplar kararlılığı miras alıyor. Blend faktörü ayrıca α = 0.3 ile
yumuşatılıyor.

Takip kaybolduğunda veya doğrulama kapısı reddettiğinde `pipeline.reset()` çağrılıyor —
boşluk üzerinden harmanlama yapılmıyor.

`GazeSmoother` (6 karelik mod filtresi) yalnızca ekrandaki yön göstergesi için kaldı.

## 1.4b Davranış durum makinesi ✅

`Core/BehaviorFSM.swift` — referanstan birebir port. 4 durum, histerezis (15°/25°),
kafa açısı zorlaması (yaw 20°, pitch 15°), 0.4 sn sönme / 0.2 sn doğma. Çıktısı
`blend ∈ [0,1]`.

**Mimari karar:** FSM'i her zaman **Yöntem A'nın** bakış açısı besler, düzeltme vektörü
Yöntem B'den gelse bile. Sebebi: FSM'in bilmesi gereken şey "kullanıcı kameradan ne kadar
uzağa bakıyor"dur ve bunu yalnızca iris söyleyebilir. Yöntem B'nin açısı ekrana bakan
biri için sabite yakındır ve "notlarına baktı" durumunu hiç göremez.

## 1.5 Eye correction ✅ — üç yöntem

`Core/GazePipeline.swift` politikayı belirler, `EyeCorrectionProcessor.swift` uygular.

| Mod | Nasıl çalışır | Dosya |
|---|---|---|
| **DeepWarp** (varsayılan) | Öğrenilmiş model gözü **sentezler** | `Core/DeepWarpModel.swift` |
| Geometri | İris'i, kamera geometrisinden gelen hedefe rijit taşır | `Core/GazeGeometry3D.swift` |
| İris | İris'i göz merkezine çeker, dikey sönümlü | `Core/IrisGazeEstimator.swift` |

Üçü de aynı kontur maskesinden geçer, yani göz kapağı koruması ortaktır.

### DeepWarp yolu

Model girdileri (göz başına, L ve R için ayrı ağırlıklar):

| Girdi | Şekil | Kaynak |
|---|---|---|
| Göz görüntüsü | 48×64×3, [0,1] | Asimetrik kırpma kutusu (aşağıda) |
| Anchor map | 48×64×12 | 6 göz noktası × (Δx, Δy) |
| Açı | 2 | `GazeGeometry3D` → (dikey, yatay) **derece** |

**Kırpma kutusu** (referanstan birebir): yarı-genişlik = göz genişliği × 3/4,
yükseklik = 1.5 × yarı-genişlik, merkeze göre asimetrik yerleşim (7/12 üst, 5/12 alt).
Asimetri kasıtlı: üst göz kapağı ve kaş gölgesi kadraja girsin diye.

⚠️ **Açıya `gain` uygulanmaz.** Model *fiziksel* bir açıya duyarlıdır; piksel warp'ının
debug çarpanını buraya uygulamak birim hatasıdır ve modeli eğitim aralığının dışına
iterek ışık düzeltme modülünün beyaz palete doymasına yol açar — gözün üstüne beyaz
leke basar (EXP-008). Açı ayrıca `maxModelAngleDeg = 30°` ile clamp'lenir.

### Geometrik yollar (yedek)

Model veya anchor noktaları yoksa buraya düşülür. Göz içi **tek rijit parça olarak**
taşınır (`CGAffineTransform` + `clampedToExtent`), sonra maskeyle harmanlanır.
Rijit taşıma seçilmesinin sebebi: sönümlü bir "çekme" kernel'i, kayma iris yarıçapını
aştığında eski iris'i yerinde bırakıp üstüne kopyasını koyuyordu — çift/hayalet iris
(EXP-005). Rijit taşıma bijektiftir; eski iris'in yerini onunla kayan sklera doldurur.

| Sabit | Değer |
|---|---|
| Varsayılan güç | 0.70 |
| Maks. kayma | göz genişliği × 0.45 |
| Maske feather | göz genişliği × 0.22 |
| Maske dilate | göz genişliği × 0.20 |

Metal shader'ı kaldırıldı; artık tüm görüntü işleme Core Image ve ONNX üzerinden.


---

## Bilinen kod problemleri

Aşağıdakiler **kodda doğrulanmış** gözlemlerdir; tahmin değildir.

> **Not:** P1 ve P2'nin çözümleri o günkü Metal tabanlı warp'a aitti. Metal yolu daha
> sonra tamamen kaldırıldı (EXP-005 → rijit taşıma, EXP-008 → DeepWarp modeli); kayıtlar
> hatanın *nasıl* bulunduğunu belgelemek için duruyor.

### ~~P1 — `maxPixelShift` Metal yolunda hiç uygulanmıyor~~ ✅ ÇÖZÜLDÜ (2026-09-01)
Eski kodda `dispX`/`dispY` hesaplanıp 20 piksele clamp ediliyor ama Metal yoluna
gönderilmiyordu; kernel farkı GPU'da yeniden hesaplıyordu, yani tavan hiç uygulanmıyordu.

Çözüm: kernel artık iki nokta değil **hazır bir deplasman vektörü** alıyor
(`GaussianEyeWarp.metal`). Clamp `GazePipeline.makeWarp` içinde yapılıyor ve GPU'ya
clamp'lenmiş değer gidiyor. Ayrıca tavan sabit 20 px yerine **göz genişliğinin %35'i** —
çözünürlükten ve kameraya uzaklıktan bağımsız.

### ~~P2 — Warp her göz için tüm kareye uygulanıyor~~ ✅ ÇÖZÜLDÜ (2026-09-01)
`EyeWarpKernel.apply(to:warp:)` artık kernel'i yalnızca `warp.roi` üzerinde çalıştırıp
sonucu `composited(over:)` ile kareye geri koyuyor. ROI, göz sınırlayıcı kutusunun
**2.5σ** genişletilmişi; o mesafede Gaussian ağırlığı ~%4 olduğu için kırpma sınırı
dikiş bırakmıyor. İki tam kare GPU geçişi ortadan kalktı.

### ~~P3 — Koordinat matematiği iki yerde~~ ✅ ÇÖZÜLDÜ (2026-09-01)
Vision → piksel dönüşümlerinin tamamı artık tek bir yerde: `VisionFaceAdapter`, ve o da
`VisionCoordinateMapper`'ı kullanıyor. `EyeCorrectionProcessor` artık hiç koordinat
matematiği içermiyor — yalnızca hazır bir `CorrectionPlan`'ı uyguluyor.

### ~~P4 — Açık/kapalı titremesi~~ ✅ ÇÖZÜLDÜ (2026-09-01)
Ayrık `direction != .center` eşiği kaldırıldı. Düzeltme artık sürekli:
davranış FSM'i `blend ∈ [0,1]` üretiyor, blend EMA ile yumuşatılıyor, ve deplasman
`güç × gain × blend` ile ölçekleniyor. Bakış merkezdeyken düzeltme vektörünün kendisi
zaten ~0 olduğu için ayrı bir eşiğe gerek yok.

### P5 — Head pose bakış *vektörüne* hâlâ girmiyor — kısmen ele alındı
Yaw/pitch artık davranış FSM'ini besliyor (kafa 20°/15°'yi aşınca düzeltme anında
çekiliyor). Ancak düzeltme **vektörünün** hesabına hâlâ girmiyor: kafa 15° dönükken
iris offset'i farklı yorumlanmalı, şu an yorumlanmıyor. MediaPipe'tan sonra ele alınacak.

### P6 — Aynalama ve koordinat ekseni doğrulanmadı — AÇIK
Ön kamera aynalaması ayarlanmamış, Vision orientation `.up`. Düzeltme yanlış yöne
gidiyorsa ilk bakılacak yer burasıdır ve bu, ADR-001'in çözmeyeceği bir problemdir.

Artık teşhisi kolay: debug katmanı her göz için **iris'ten hedefe pembe bir ok** çiziyor.
Ok yukarıyı gösteriyorsa dikey yön doğru. Yatay yön için `GazeGeometry3D.Calibration`
içinde `invertHorizontal` bayrağı var (varsayılan `false`, **doğrulanmadı**).

### P7 — Yöntem B'nin yatay işaret yönü doğrulanmadı — AÇIK
3B geometri yönteminin dikey işareti fizikten türetildi ve gerekçesi kodda yazılı
(pozitif açı = bakışı yukarı çevir). **Yatay işaret aynı güvenle türetilmedi** —
referans projenin x ekseni görüntü-soluna bakıyor gibi görünüyor. Kamera genelde yatayda
ortalı olduğu için (`cameraOffset.x = 0`) yatay düzeltme küçük kalıyor, bu yüzden acil
değil; ama gözle doğrulanmalı.

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

## 2.8 Öğrenilmiş warp — DeepWarp ✅ **implement edildi**

> Bu bölüm modelin tam tanımıdır. Swift implementasyonu: `Core/DeepWarpModel.swift`.
> TF1 → ONNX dönüşümü EXP-007'de sayısal olarak doğrulandı (fark ~2–3×10⁻⁵).

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

✅ **Ağırlıklar elimizde.** Orijinal projenin GitHub Releases sayfasından indirildi
(`v0.1.1`, `weights.zip`, 5.9 MB) → `models/deepwarp/weights/warping_model/flx/12/{L,R}`.
ONNX'e çevrilmiş halleri `apps/macos/EyesOn/deepwarp_{L,R}.onnx` (~1.05 MB / göz).

Dönüşüm betiği: `scratchpad/convert_deepwarp.py`. Model güncellenirse aynı sayısal
karşılaştırma tekrar çalıştırılmalıdır.

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
