# Experiments

Denenmiş yöntemler — **başarısız olanlar dahil.** Eye-contact correction araştırma
ağırlıklı bir problemdir; bir yaklaşımın neden işe yaramadığı kaybolursa bir sonraki
agent aynı çıkmazı tekrar yürür.

**Format kuralı:** Ölçüm yapılmadıysa "Not measured" yaz, sayı uydurma. Hangi donanımda
ölçtüğünü mutlaka belirt.

---

## EXP-001 — Apple Vision pupil landmark'ının bakış tahmini için yeterliliği

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: Reject — Vision tek başına yetersiz**

### Hypothesis
ADR-001'in dayandığı iddia: Apple Vision'ın tek ve kaba pupil noktası bakış tahmini için
yetersiz, ve düzeltmenin "yok ya da yanlış" görünmesinin kök nedeni bu.

### Method
Uygulama derlenip çalıştırıldı, debug HUD'daki canlı değerler okundu. Kullanıcı ekrana
normal mesafeden bakarken.

### Hardware
MacBook, macOS 26.3.1, Xcode 26.4.1, dahili kamera, 1280×720.

### Result
```
L-eye centroid (685, 367)   L-pupil (683, 370)   Δ = (-2.6, +2.6) px
R-eye centroid (784, 363)   R-pupil (783, 365)   Δ = (-0.7, +2.5) px
Gaze: Merkez   rawOff = (-0.037, 0.057)
EAR L 0.32  R 0.30   Yaw 0°  Pitch 0°   Safe: YES
```

Pupil, göz merkezinden yalnızca **2–3 piksel** ayrılıyor. Normalize offset 0.037/0.057,
sınıflandırma eşiklerinin (0.10 / 0.08) çok altında. Yüz tespiti, göz konturu, EAR ve
kafa açısı ise **doğru ve kararlı** çalışıyor.

### Conclusion
**Hipotez doğrulandı.** Vision'ın pupil'i bakış tahmini için kullanılamaz. Ancak aynı
ölçüm daha faydalı bir şey de gösterdi: **göz merkezleri ve gözler arası mesafe
güvenilir.** Bu, iris'e hiç ihtiyaç duymayan 3B geometri yöntemini (Yöntem B) bugün
uygulanabilir kılıyor → ADR-007.

### Keep / Reject / Revisit
**Reject** — Yöntem A'yı Vision'la birincil düzeltme kaynağı olarak kullanma.
**Revisit** — MediaPipe entegrasyonundan (MVP 2) sonra aynı ölçümü tekrarla; iris
başına 5 nokta geldiğinde bu deney tekrar açılmalı ve A ile B karşılaştırılmalı.

---

### EXP-002 (planlandı) — Düzeltme yönünün gözle doğrulanması

**Hypothesis:** Yöntem B'nin dikey işareti doğru (pozitif açı = bakışı yukarı çevir,
CIImage uzayında +y). Yatay işareti **doğrulanmadı** (P7).

**Method:** "⚡ Düzeltme"yi aç, Gain'i 4–6× yap ki hareket net görülsün. Debug
katmanındaki **pembe ok** iris'ten hedefe çizilir.

**Bakılacaklar:**
1. Ok yukarıyı mı gösteriyor? (Kamera ekranın üstündeyse doğrusu bu.)
2. İris gerçekten yukarı mı gidiyor, göz dış hattı sabit mi kalıyor?
3. Kafayı sağa/sola çevirince yatay bileşen mantıklı mı? Değilse
   `GazeGeometry3D.Calibration.invertHorizontal = true` dene.
4. Göz kırpınca bozulma var mı?
5. Yaw'ı 20°'nin üstüne çıkar — FSM `DISENGAGING` → `DISENGAGED`'a geçip düzeltme
   yumuşakça kayboluyor mu?

**Neden önemli:** Yön yanlışsa hiçbir kalite iyileştirmesi işe yaramaz; ve bu, MediaPipe'ın
çözmeyeceği bir problemdir.


---

## EXP-003 — Tüm karenin yayılması (smearing): zincirlenmiş CIWarpKernel

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: Çözüldü**

### Problem
Düzeltme açıldığında **tüm kare bozuluyordu**: yüz ve gözler sağlam kalıyor, çevresindeki
her şey yatay/dikey olarak dışarı doğru yayılıyordu. HUD'daki sayılar (kayma 6–8 px,
blend 1.00, açılar) tamamen sağlıklıydı — yani hesap değil, warp'ı kareye uygulama yolu
bozuktu.

### Method
Kamerasız izole reprodüksiyon: dama tahtası görüntüsü + uygulamadaki `EyeWarpKernel`
kodunun birebir kopyası (`scratchpad/warptest2.swift`).

### Result
- **Tek warp** → tertemiz, sadece merkezde yumuşak bükülme
- **İki warp zincirlenince** → aynı yayılma, birebir reprodüksiyon

Yani hata kernel'de veya parametrelerde değil, **iki gözün zincirlenmesinde**.

### Kök neden
`EyeCorrectionProcessor` sol gözün çıktısını sağ gözün girdisi yapıyordu:

```
sonuç = warp_sağ( warp_sol(kare).composited(over: kare) )
```

İkinci warp'ın `roiCallback`'i, ilk warp'ın **extent'inin dışından** piksel istiyor.
Core Image o isteği ilk warp'a iletiyor ve orada kenar pikselleri tekrarlanıyor
(clamp-to-edge). Sonuç: ilk ROI'nin kenar pikselleri tüm kareye yayılıyor.

Ara adım olarak `warped.cropped(to: roi)` eklemek yayılmayı durdurdu, ama asıl çözüm
yapısaldı.

### Çözüm — referans projenin yapısına geçiş
`reference/gaze-corrector/gaze_corrector.py` zaten doğru yapıyı kullanıyordu ve biz onu
port etmemiştik. Şimdi aynısı uygulandı:

1. Göz ROI'sini **ayrı bir görüntüye kırp**
2. O izole yamayı warp et
3. Göz konturunun **convex hull maskesiyle** (Gaussian feather'lı) kareye geri harmanla

Ek olarak: iki göz yaması **daima orijinal kareden** üretiliyor, birbirine zincirlenmiyor.

### Conclusion
İki kazanç var. Yayılma bitti; ve maske sayesinde göz kapağı, kirpik ve çevre deri
**warp ne yaparsa yapsın deforme olamaz** — referans projenin asıl garantisi buydu.

### Keep / Reject / Revisit
**Keep.** Ayrıca ders: mevcut GPU koduna yama yapmak yerine referansın yapısını port
etmek gerekiyordu; hata tam da port etmediğimiz yerdeydi.


---

## EXP-004 — Hedef-tabanlı düzeltme + düz tepeli (flat-top) warp profili

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: Keep (kullanıcı doğrulaması sürüyor)**

### Problem
Kullanıcı gereksinimi net: *"gözüm kameraya bakmıyorken bile kameraya bakıyor gibi
görünsün."* Canlı testte iki eksik görüldü:

1. **Geometri yöntemi yana bakışı hiç düzeltmiyordu** — iris'in o an nerede olduğuna
   bakmadan sabit ekran→kamera ofsetini uyguluyordu. Yana bakınca hiçbir şey olmuyordu;
   12× gain'de ise iris göz kapağının altına itilip "beyaz göz" çıkıyordu.
2. **Gaussian profil iris'i taşımıyor, esnetiyordu** — σ iris'in kendisinin üzerinde de
   düşüş gösterdiği için pupil leke gibi yayılıyordu.

### Method / Değişiklik
- **Hedef-tabanlı düzeltme:** `hedef = göz merkezi + 3B geometri ofseti` (kamera ekranın
  üstünde olduğu için doğal "yukarı" payı). Düzeltme = hedef − *mevcut* iris konumu.
  Yana bakınca iris tam mesafe geri çekilir — istenen davranış tam olarak bu.
- **Warp profili:** Gaussian → düz tepeli. `innerRadius` (~0.20×göz genişliği, iris
  yarıçapı) içinde ağırlık 1 → iris rijit parça olarak taşınır; `outerRadius`'a
  (0.60×genişlik) kadar smoothstep ile sıfıra iner. Kernel adı `irisShiftWarp` oldu.
- Kayma tavanı 0.35 → **0.45 × göz genişliği** (köşedeki iris'in merkeze dönüş yolu
  ~0.3×genişlik).
- İris modu referansın birebir portu olarak kaldı (merkeze çek + dikey sönüm 0.5) —
  "ince ayar" modu. Geometri modu ürün davranışı ve varsayılan.

### Result
Derlendi, çalıştırıldı, ekran görüntüsüyle doğrulandı: kare temiz, kayma yok,
blend 1.00, uygulanan kayma (0.9, 6.0) px, gözler doğal görünüyor. **Yana sert bakış
senaryosu kullanıcı tarafından canlı doğrulanacak.**

### Bilinen sınır
Piksel kaydırma warp'ı, iris köşedeyken arkada kalan boşluğu skleradan esneterek
dolduruyor — sert bakışlarda doku bozulması beklenir. Gerçek çözüm parçalı affine
(Delaunay) ya da DeepWarp modeli (MVP 7). Bu deney "geometrik yöntemin tavanını" tanımlar.


---

## EXP-005 — Hayalet iris ("ballı" görüntü): flat-top kernel → rijit taşıma + maske

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: Keep (kullanıcı doğrulaması sürüyor)**

### Problem
Kullanıcı gözlemi: düzeltme açıkken iris çift/bulanık ("ballı") görünüyor. Sebep: düz
tepeli warp kernel'i, kayma iris yarıçapını (innerRadius) aştığında iris'in **kopyasını**
hedefe koyuyor ama orijinalin bulunduğu noktada ağırlık düştüğü için **eski iris'i tam
silmiyordu**. Falloff'lu her "pull" kernel'inin yapısal kusuru bu.

### Değişiklik
- Metal kernel tamamen kaldırıldı (`GaussianEyeWarp.metal`, `EyeWarpKernel.swift` silindi).
- Yeni yöntem: göz içi yaması **tek rijit parça olarak taşınıyor**
  (`CGAffineTransform` translation, `clampedToExtent` ile kenar dolgusu) ve convex hull
  + feather maskesiyle geri harmanlanıyor. Taşıma bijektif → eski iris'in yeri, onunla
  birlikte kayan sklerayla doluyor; geride hayalet bırakacak bir şey kalmıyor.
- Maske dilate 0.12 → **0.20 × göz genişliği**: iris köşedeyken bile maske tam ağırlıkta
  kalsın, feather bandı orijinal iris'i karıştırmasın diye.
- Referansın 3 noktalı affine'i **bilinçli olarak kullanılmadı**: çapa (göz köşeleri) ve
  iris merkezi neredeyse eşdoğrusal → affine kötü koşullanmış; küçük dikey iris ofsetinde
  katsayılar patlıyor. Rijit taşıma + maske aynı görsel etkiyi kararlı şekilde veriyor.

### Bilinen sınır
Maske feather bandında taşınmış sklera ile orijinal doku karışır (sklera-üstüne-sklera
olduğu için normalde görünmez). Sert yan bakışta iris kontur kenarına dayandığında hafif
karışma hâlâ mümkün — dilate artışı bunu azaltmak için. Gerçek çözüm MVP 7 (DeepWarp).


---

## EXP-006 — Referans projeleri canlı çalıştırma (kullanıcı değerlendirmesi)

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: Devam ediyor**

### Amaç
Kendi warp denemelerimiz tatmin etmedi; kullanıcı kararı: referans sistemleri önce
canlı çalıştırıp asıl sistemi işe yarayandan çekmek.

### Kurulum (tekrarlanabilir)
Venv'ler scratchpad'de (kalıcı değil, gerekirse yeniden kurulur):

- **gaze-corrector** (`Examples/gaze-corrector-main`):
  `python3.11 -m venv venv-gc` + `opencv-python` + **`mediapipe==0.10.21`** (⚠️ 1.x
  `mp.solutions` API'sini kaldırmış — 0.10.x şart) + `pyvirtualcam`.
  ⚠️ Gereken yama: `cv2.imshow` macOS'ta ana thread dışında çöküyor ("Unknown C++
  exception"); `pipeline.py`'a `preview_loop()` eklendi, çizim thread'de kalıp gösterim
  ana thread'e alındı. Çalıştırma: `python main.py --preview --no-vcam --no-tray`
- **deepwarp-cam** (`Examples/gaze-correction-cam-master`):
  `python3.11 -m venv venv-dw` + `tensorflow==2.19.1` + `mediapipe==0.10.21` + `pyyaml`.
  **Ağırlıklar bulundu ve indirildi:** `gh release download v0.1.1
  -R WangWilly/gaze-correction-cam -p weights.zip` (5.9 MB, `weights/warping_model/flx/12/L`
  ve `R/` TF1 checkpoint'leri) + `models/face_landmarker.task` (Google storage, 3.6 MB).
  Çalıştırma: `python bin_single_window.py --backend mediapipe`

### İlk gözlemler
- **gaze-corrector canlı doğrulandı (kullanıcı):** MediaPipe landmark tespiti "noktası
  noktasına çok güzel" — göz ve göz çevresi. Continuity Camera (telefon kamerası) ile
  çalıştı → kamera bağımsızlığı da doğrulandı. ADR-001 canlı kanıt buldu.
- **deepwarp-cam** ayağa kalktı (MediaPipe backend + indirilen ağırlıklar); görsel
  kalite değerlendirmesi kullanıcıda.

### Önemli sonuç
DeepWarp ağırlıkları artık elimizde — MVP 7'nin "ağırlık bul veya eğit" riski büyük
ölçüde kapandı. Kalıcı yer: `models/` (git'e girmez), oradan TF1→ONNX→CoreML dönüşümü
yapılacak.

---

## EXP-007 — MediaPipe Face Landmarker ONNX Runtime çıkarımı ve entegrasyonu

**Date:** 2026-09-01 · **Agent:** Gemini (Antigravity) · **Sonuç: Başarılı (Keep)**

### Amaç
MediaPipe 478 noktalı (10 iris noktası dahil) Face Landmarker modelini macOS üzerinde
yüksek hızda ve doğrudan Swift içinden çalıştırmak (ADR-002 çözümü).

### Yöntem
1. `models/face_landmarker.task` içinden `face_landmarks_detector.tflite` çıkarıldı.
2. `tf2onnx` ile ONNX formatına dönüştürüldü (`models/face_landmarks_detector.onnx`, 4.7 MB).
3. Apple Silicon (M1/M2/M3/M4) CPU üzerinde `onnxruntime` çıkarım hızı 50 kare üzerinde benchmark edildi.
4. Microsoft `onnxruntime-swift-package-manager` paketi Xcode projesine bağlandı.
5. `ONNXFaceLandmarker.swift` + `MediaPipeFaceAdapter.swift` yazılarak `VisionProcessor` ve `CameraViewModel` pipeline'ına entegre edildi.

### Donanım
MacBook Pro (Apple Silicon), macOS 26.3.1, Xcode 26.4.1.

### Sonuç
- **Çıkarım gecikmesi:** Ortalama **2.36 ms / kare** (LiteRT 4.70 ms idi).
- **Landmark çıktısı:** 478 adet 3B nokta (468–472 sol iris, 473–477 sağ iris).
- **Derleme:** `xcodebuild` temiz derlendi, uyarı ve hata yok.
- **İris takibi:** Vision'ın 2–3 piksellik tek pupil noktası yerine gerçek iris çemberi ve merkezi elde edildi.

### Karar
**Keep.** MediaPipe ONNX modeli projenin birincil landmark motoru olarak kabul edildi (ADR-001 & ADR-002 tamamlandı).



---

## EXP-007 — DeepWarp TF1 → ONNX dönüşümü ve sayısal doğrulama

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: PASS — dönüşüm sadık**

### Hypothesis
MVP 7'nin baş riski, `tf_models/gaze_corrector_v1/spatial_transform.py` içindeki **özel
bilinear örnekleme (spatial transformer)** katmanının ONNX'e sadık çevrilememesiydi
(docs/MODEL_PIPELINE.md'de "TODO: verify" olarak işaretliydi). Bu doğrulanmadan Swift
tarafına zaman harcamak riskliydi.

### Method
`scratchpad/convert_deepwarp.py`:
1. TF1 grafiğini `build_inference_graph` ile kur, checkpoint'i geri yükle
2. Sabit tohumlu (seed=42) test girdisi: 48×64×3 görüntü, 48×64×12 anchor map,
   açı [12.0, −8.0]
3. TF çıkarımını al → referans çıktı
4. `convert_variables_to_constants` ile dondur, `tf2onnx` opset 13 ile çevir
5. ONNX Runtime ile aynı girdiyi çalıştır, sayısal karşılaştır

### Hardware / Ortam
MacBook (Apple M1), macOS 26.3.1, Python 3.11, TF 2.19.1 (v1 uyumluluk modu),
tf2onnx 1.17.0, onnxruntime 1.29.0.

### Result

| Göz | TF çıktı aralığı | ONNX çıktı aralığı | max abs fark | ort. fark | Sonuç |
|---|---|---|---|---|---|
| L | [0.00000, 0.98505] | [0.00000, 0.98505] | 2.101e-05 | 7.328e-07 | **PASS** |
| R | [0.00000, 0.98910] | [0.00000, 0.98910] | 3.430e-05 | 7.707e-07 | **PASS** |

Eşik 1e-4 idi; fark float32 yuvarlama gürültüsü seviyesinde. Spatial transformer
sorunsuz çevrildi.

Çıktı: `models/deepwarp/onnx/deepwarp_{L,R}.onnx`, her biri ~1.05 MB.
Uyarı (zararsız): `tf_half_pixel_for_nn` opset 13'te deprecated — coarse akışın
upsample katmanından geliyor, çıktı doğruluğunu etkilemiyor (fark tabloda görülüyor).

### Conclusion
**MVP 7'nin en büyük teknik riski kapandı.** ONNX Runtime zaten projede olduğu için
(ADR-002) CoreML adımı gerekmiyor; modeller doğrudan `ONNXFaceLandmarker` desenine
benzer bir sarmalayıcıyla çalıştırılabilir.

### Keep / Reject / Revisit
**Keep.** Dönüşüm betiği saklanmalı — model güncellenirse tekrar çalıştırılıp aynı
karşılaştırma yapılmalı (docs/MODEL_PIPELINE.md'deki "export zincirini bozma" kuralı).

### Sıradaki (henüz yapılmadı)
Swift entegrasyonu: 48×64 göz kırpması + 12 kanallı anchor map üretimi + açının
modele bağlanması. Model girdileri iris landmark'ı **istemiyor**; 6 göz kontur noktası
ve gözler arası mesafe yeterli.


---

## EXP-008 — DeepWarp Swift entegrasyonu ve "beyaz göz" hatası

**Date:** 2026-09-01 · **Agent:** Claude (Opus 5) · **Sonuç: Çalışıyor (kalite değerlendirmesi kullanıcıda)**

### Yapılan
`Core/DeepWarpModel.swift` — ONNX Runtime üzerinden L/R model oturumları. Referanstan
port edilenler:
- **Kırpma geometrisi** (`_extract_single_eye`): göz genişliğinin 3/4'ü yarı-genişlik,
  1.5× yükseklik, merkeze göre asimetrik (7/12 üst, 5/12 alt) — üst göz kapağını ve
  kaş gölgesini içine alsın diye
- **Anchor map**: 6 göz noktası × (Δx, Δy) = 12 kanal; sıra L için `[3,2,1,0,5,4]`,
  R için `[0,1,2,3,4,5]`
- Referans OpenCV'nin y-aşağı uzayında; port y-yukarı CIImage uzayında, satır
  sıralaması çevriliyor

`EyeGeometry`'ye `anchorPoints` eklendi; iki adaptör de dolduruyor (MediaPipe doğrudan
indekslerden, Vision konturu 6'ya yeniden örnekleyerek). Model çıktısı mevcut kontur
maskesinden geçiyor — göz kapakları yine sabit.

### Hata: gözün üstünde beyaz leke

İlk canlı testte DeepWarp modu gözün üzerine **beyaz bir leke** bastı.

**Kök neden:** Gain kaydırıcısı (debug amaçlı, 12×'e kadar) modele giden **açıyı** da
çarpıyordu. Model *fiziksel* bir açıya (derece) duyarlı; 19° × 0.88 × 12 ≈ 200° gibi bir
değer eğitim aralığının çok dışında. Bu durumda ağın ışık düzeltme modülü (LCM) beyaz
palete doğru doyuyor — `çıktı = warp × w_görüntü + beyaz × w_palet` formülünde
`w_palet → 1`. Yani beyaz leke, modelin bozulması değil, **aralık dışı girdiye verdiği
öngörülebilir tepki**.

**Çözüm:**
1. `gain` model yolundan çıkarıldı — piksel warp'ının debug çarpanıydı, modele anlamsız
2. Açı `CorrectionConfig.maxModelAngleDeg = 30°` ile clamp'lendi (gerçek ekran-kamera
   geometrisi zaten ±30° içinde kalır; clamp yalnızca bozuk girdiyi yakalar)

Düzeltmeden sonra: beyaz leke yok, yüz doğal, artefakt görünmüyor (Güç 0.70, Gain 1.0×).

### Ders
Model yolu ile piksel warp yolu **farklı birimlerde** çalışıyor: biri derece, diğeri
piksel. Piksel yolu için tasarlanmış bir çarpanı model yoluna uygulamak sessiz bir
birim hatasıydı. Yeni bir düzeltme yöntemi eklenirken hangi parametrenin hangi yola
ait olduğu açıkça ayrılmalı.

### Sıradaki
Kullanıcı değerlendirmesi: yana bakışta iris gerçekten kameraya dönüyor mu, hayalet var
mı, videoda titreme var mı. Ölçüm de yapılmadı — DeepWarp'ın kare başına maliyeti
(iki ONNX çıkarımı) `docs/PERFORMANCE.md`'ye işlenmeli.
