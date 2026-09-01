# Decisions (ADR)

Kalıcı mimari kararlar. **Yeni bilgi olmadan bunları yeniden tartışma.**
Yeni bir karar verdiğinde aynı formatta ekle ve numarayı artır.

---

## ADR-001 — Landmark motoru: Apple Vision yerine MediaPipe

**Status:** Accepted · 2026-08-29

### Context
Mevcut macOS uygulaması yüz ve göz landmark'ları için Apple Vision'ın
`VNDetectFaceLandmarksRequest` API'sini kullanıyor. Bakış tahmini
(`GazeEstimator.swift`) doğrudan `VNFaceLandmarks2D.leftPupil` / `rightPupil`
değerlerine dayanıyor. Son commit mesajı düzeltmenin "yok ya da yanlış" olduğunu
söylüyor.

### Decision
Landmark kaynağı MediaPipe Face Landmarker (`refine_landmarks = true`, 478 nokta)
olacak.

### Alternatives
- **Apple Vision'da kalmak** — macOS'ta sıfır bağımlılık, kod zaten yazılmış
- **dlib 68 nokta** — `reference/deepwarp-cam` bunu destekliyor
- **Hibrit** — Vision + yalnızca iris için ikinci bir model

### Reason
- Apple Vision göz başına **tek ve kaba bir pupil noktası** verir. MediaPipe göz başına
  **5 iris noktası** (468–472 sol, 473–477 sağ) verir. Bakış tahmini iris konumuna
  doğrudan bağlı olduğu için bu, mevcut düzeltmenin yanlış görünmesinin en olası kök
  nedenidir. *(Not: bu bir hipotezdir, MVP 1'de ölçümle doğrulanacak.)*
- Apple Vision yalnızca Apple platformlarında vardır. Windows ve Android'de bakış
  tahminini sıfırdan yazmak gerekirdi. MediaPipe macOS/Windows/iOS/Android/Web'de
  aynı modeli çalıştırır.
- Her iki referans proje de MediaPipe topolojisini kullanıyor; landmark indeksleri ve
  tüm eşik değerleri buna göre kalibre edilmiş durumda.
- dlib'de iris yok, yalnızca göz konturu var.

### Consequences
- ~3–4 MB model dosyası dağıtıma eklenir (`models/`, git'e girmez)
- C++ bağımlılığı ve Swift köprü kodu gerekir
- macOS'ta MediaPipe'ı **nasıl** çalıştıracağımız ayrı ve henüz açık bir sorudur → ADR-002
- Mevcut `GazeEstimator.swift`, `LandmarkValidator.swift` ve `EyeCorrectionProcessor.swift`
  landmark kaynağından soyutlanmalı; şu an `VNFaceObservation` tipine sıkı bağlılar

---

## ADR-002 — macOS'ta MediaPipe çalıştırma yolu: ONNX Runtime

**Status:** Accepted · 2026-09-01

### Context
MediaPipe Tasks'ın resmî Swift dağıtımı (`MediaPipeTasksVision` CocoaPod) iOS'u hedefler.
macOS üzerinde 478 MediaPipe landmark'ını (10 iris noktası dahil) yüksek hızda ve sıfır
derleme sancısıyla çalıştırmamız gerekiyordu.

### Decision
`face_landmarks_detector.tflite` modeli ONNX formatına dönüştürüldü (`models/face_landmarks_detector.onnx`).
macOS uygulamasına Microsoft'un resmî `microsoft/onnxruntime-swift-package-manager` (SPM)
paketi bağlandı ve `ONNXFaceLandmarker.swift` üzerinden doğrudan çalıştırıldı.

### Alternatives
- Bazel ile MediaPipe C++ derlemek — çok ağır geliştirme/CI maliyeti.
- CoreML doğrudan dönüşüm — tflite2coreml özel pooling/conv opsiyonlarında uyumsuzluk verdi.
- TFLite C library — SPM desteği eksik, macOS için manuel xcframework gerektiriyor.

### Reason
- **Performans:** Apple Silicon üzerinde ortalama **2.36 ms / kare** çıkarım süresi (60+ fps hedefinin çok ötesinde).
- **Entegrasyon kolaylığı:** Xcode SPM üzerinden temiz bağımlılık yönetimi.
- **Platform uyumluluğu:** Windows aşamasında da aynı ONNX modeli ve ONNX Runtime doğrudan kullanılabilecek.

### Consequences
- `face_landmarks_detector.onnx` (4.7 MB) bundle içine eklendi.
- `ONNXFaceLandmarker` 478 3B landmark'ı (10 iris noktası dahil) piksel koordinatlarıyla üretir.
- `MediaPipeFaceAdapter` ile landmark kaynağı Vision'dan MediaPipe'a taşındı.

---

## ADR-003 — Warp yöntemi: önce geometrik, sonra öğrenilmiş model

**Status:** Accepted · 2026-08-29

### Context
`reference/` altında iki farklı göz düzeltme yaklaşımı var: geometrik warp
(`gaze-corrector`) ve öğrenilmiş DeepWarp modeli (`deepwarp-cam`). Mevcut macOS kodu
üçüncü bir varyant kullanıyor: Metal Gaussian warp kernel'i.

### Decision
MVP 3–4'te geometrik warp ile ilerlenecek. Öğrenilmiş model MVP 7'ye ertelendi.

### Alternatives
- Doğrudan DeepWarp modeline geçmek
- Yeni bir model sıfırdan eğitmek

### Reason
DeepWarp ağırlıkları **elimizde yok.** `reference/deepwarp-cam` yalnızca mimariyi içerir;
checkpoint dosyaları orijinal projenin GitHub Releases sayfasından indirilmeli ya da
sıfırdan eğitilmeli — ikisi de belirsiz süreli. Geometrik warp bugün çalışır ve boru
hattının geri kalanını (FSM, temporal stabilizasyon, virtual camera) doğrulamamızı sağlar.
Model geldiğinde yalnızca pipeline'ın tek bir aşaması değişir.

### Consequences
Warp aşaması, çıkarılabilir bir arayüzün arkasında tutulmalı ki MVP 7'de yerine model
konabilsin.

---

## ADR-004 — Monorepo hiyerarşi; uygulamalar `apps/` altında

**Status:** Accepted · 2026-08-29

### Context
Beş platform hedefleniyor. Xcode projesi repository kökündeydi.

### Decision
`apps/macos/EyesOn.xcodeproj` + `apps/macos/EyesOn/`. Kök dizin `docs/`, `.ai/`, `apps/`,
`core/`, `models/`, `reference/` ile organize edildi. Taşıma `git mv` ile yapıldı.

### Alternatives
- macOS'u kökte bırakıp diğer platformları alt klasörlere koymak
- Her platform için ayrı repository

### Reason
macOS'u kökte bırakmak, Windows eklendiğinde asimetrik ve kafa karıştırıcı bir yapı
üretirdi. Ayrı repository'ler paylaşılan çekirdeği ve ortak AI hafızasını böler.
Taşıma güvenliydi: `project.pbxproj` `objectVersion 77` (Xcode 16 senkronize klasör
grupları) kullanıyor ve içinde mutlak yol yok — `.xcodeproj` ile kaynak klasörü birlikte
taşındığı için göreli ilişki korundu.

### Consequences
⚠️ Derleme ile **doğrulanmadı.** MVP 1'in ilk işi bu.

---

## ADR-005 — `Examples/` silinecek, `reference/` kalacak

**Status:** Accepted · 2026-08-29

### Context
`Examples/` klasörü 4.9 GB'tı ve dört alt proje içeriyordu.

### Decision
`Examples/` git'te izlenmiyor ve iş bitince silinecek. Değerli kaynak kod `reference/`
altına kopyalandı ve git'e alındı. **Hiçbir kod, doküman veya betik `Examples/` içine
referans veremez.**

### Alternatives
- Tümünü git'e almak (4.9 GB — pratik değil)
- Git submodule olarak bağlamak (orijinal repolar upstream'de değişebilir)

### Reason
- `Examples/EyesOnAI`: 4.8 GB'ın tamamı Python venv'i; proje kodu **hiç yok**, tek commit
  bile yok. Kurulu paketler (torch, torchvision, coremltools, opencv) niyeti gösteriyor
  ama içerik yok.
- `Examples/EyesOn-main`: bu repository'nin birebir kopyası — `diff -r` ile doğrulandı.
- Kalan iki proje toplam ~4900 satır Python. Bunu izlemek bedava, 4.9 GB'ı taşımak değil.

### Consequences
`reference/` altındaki kod MIT lisanslıdır; `LICENSE` dosyaları birlikte kopyalandı.
Türetilen kodda atıf korunmalıdır.

---

## ADR-006 — Proje dili

**Status:** Accepted · 2026-08-29

Dokümanlar, commit mesajları ve kullanıcıya dönük metinler **Türkçe**.
Kod, tanımlayıcılar ve kod içi yorumlar **İngilizce**.

Sebep: proje sahibi Türkçe çalışıyor; kod ise standart İngilizce konvansiyonlarına
uymalı ki üçüncü taraf kütüphanelerle ve gelecekteki katkıcılarla tutarlı olsun.


---

## ADR-007 — Hibrit bakış tahmini: davranış Yöntem A'dan, düzeltme Yöntem B'den

**Status:** Accepted · 2026-09-01

### Context
Referans projelerden iki farklı bakış tahmin yöntemi port edildi:

- **Yöntem A (iris offset)** — `reference/gaze-corrector`. İris'in göz merkezinden
  sapmasını ölçer. Yönü tartışmasız doğru, ama girdi kalitesine bağlı.
- **Yöntem B (3B geometri)** — `reference/deepwarp-cam`. Gözün 3B konumunu gözler arası
  mesafeden çıkarır, kameraya bakmak için gereken dönme açısını hesaplar. **İris'e hiç
  bakmaz.**

Canlı uygulamada ölçüldü: Apple Vision'ın pupil noktası göz merkezinden yalnızca
**2–3 piksel** ayrılıyor (`rawOff ≈ (-0.037, 0.057)`), eşiklerin (0.10 / 0.08) çok
altında. Yani Yöntem A'nın girdisi bugün pratikte sıfır.

### Decision
İkisi de çalışır, farklı işler için:

- **Düzeltme vektörü** varsayılan olarak **Yöntem B**'den gelir. Arayüzden A'ya
  geçilebilir (MediaPipe sonrası A'nın değerli olacağı yer burası).
- **Davranış FSM'i her zaman Yöntem A'nın bakış açısıyla beslenir**, düzeltme B'den
  gelse bile.

### Alternatives
- Yalnızca A — bugün neredeyse hiç düzeltme üretmez
- Yalnızca B — "kullanıcı başka yere baktı" durumunu asla göremez
- MediaPipe'ı bekleyip hiçbir şey yapmamak — boru hattının geri kalanı doğrulanmadan kalırdı

### Reason
FSM'in bilmesi gereken şey "kullanıcı kameradan ne kadar uzağa bakıyor"dur ve bunu
yalnızca iris söyleyebilir. Yöntem B'nin açısı ekrana bakan biri için sabite yakındır
(kamera ekranın 21 cm üstündeyse ~19°) ve kullanıcı notlarına baktığında **değişmez** —
çünkü göz konumu değil, iris hareket eder. B'yi FSM'e bağlamak, davranış tespitini
tamamen kör ederdi.

### Consequences
- Vision'la FSM pratikte hep ENGAGED kalır (iris sinyali zayıf). Bu güvenlidir: kafa
  açısı zorlaması (yaw 20° / pitch 15°) hâlâ çalışır ve gerçek koruma odur.
- MediaPipe geldiğinde FSM kendiliğinden anlamlı hale gelir; kod değişmez.
- ⚠️ Yöntem B'nin **yatay** işaret yönü doğrulanmadı (P7). Dikey işaret fizikten
  türetildi ve gerekçesi kodda yazılı.

---

## ADR-008 — Warp politikası CPU'da, shader saf fonksiyon

**Status:** Accepted · 2026-09-01

### Context
Eski `GaussianEyeWarp.metal` iki nokta (`pupilCenter`, `eyeCenter`) alıp farkı GPU'da
hesaplıyordu. Swift tarafında hesaplanan `maxPixelShift` clamp'i GPU'ya hiç ulaşmıyordu —
bu bir bug'dı (P1) ve sınıfsal olarak tekrar edebilir bir bug'dı.

### Decision
Kernel artık **hazır bir deplasman vektörü** alıyor. Clamp, güç, davranış blend'i —
tüm politika `GazePipeline` içinde CPU'da karara bağlanıp GPU'ya pişmiş halde gidiyor.

### Alternatives
Clamp'i shader'a taşımak — kernel'e daha çok parametre eklerdi ve politikayı test
edilemez bir yere koyardı.

### Reason
Shader'ı girdilerinin saf bir fonksiyonu yapmak, P1'in **sınıf olarak** tekrar etmesini
imkânsız kılar: GPU'ya giden değerle CPU'nun hesapladığı değer artık aynı şeydir.
Yan fayda: warp geometrisi GPU olmadan unit test edilebilir hale geldi.

### Consequences
- Eski CPU fallback'i kaldırıldı (kendi yorumunun da dediği gibi "hayalet iris"
  bırakıyordu, doğallık önceliğiyle çelişiyordu). Metal yüklenemezse düzeltme sessizce
  atlanır — kare olduğu gibi geçer, ki bu her zaman geçerli bir çıktıdır.


---

## ADR-009 — Warp izole yamada yapılır, maskeyle harmanlanır; asla zincirlenmez

**Status:** Accepted · 2026-09-01

### Context
İlk entegrasyonda referans projelerin *algoritmaları* (FSM, EMA, iris offset, 3B geometri)
port edildi ama **warp yapısı** port edilmedi; mevcut Metal Gaussian kernel'i tüm kare
üzerinde, iki göz zincirlenerek uygulandı. Bu, tüm kareyi bozan bir yayılmaya yol açtı
(EXP-003).

### Decision
`reference/gaze-corrector/gaze_corrector.py` yapısı birebir uygulanır:

1. Göz ROI'si ayrı bir görüntüye kırpılır
2. Warp yalnızca o izole yamada çalışır
3. Göz konturunun convex hull'undan Gaussian-feather'lı maske üretilir
4. Yama, maske içinde kareye harmanlanır

Ve: **her göz yaması daima orijinal kareden üretilir.** Bir gözün çıktısı diğerinin
girdisi olamaz.

### Alternatives
- Zincirin arasına `cropped(to:)` eklemek — yayılmayı durduruyordu ama maskeyi ve
  onun sağladığı göz kapağı korumasını getirmiyordu
- Tüm kare üzerinde warp'a geri dönmek — eski davranış; iki tam kare GPU geçişi

### Reason
İzole yama, bu hata **sınıfını** imkânsız kılar: ROI dışındaki hiçbir piksel grafiğin
parçası değildir. Maske ise referansın asıl katkısıdır — göz konturunun dışındaki her şey
orijinal piksellere sabitlenir, yani warp ne yaparsa yapsın göz kapağı, kirpik ve deri
deforme olamaz. Bu, [AGENTS.md](../AGENTS.md) önceliklerindeki 1. madde (natural visual
quality) için pazarlık konusu değildir.

### Consequences
- Kare başına iki küçük CGContext maske çizimi eklendi (ROI ~200×160, ihmal edilebilir)
- `EyeWarp` artık göz konturunu ve feather yarıçapını taşıyor
- Feather ve dilate, sabit piksel yerine göz genişliğinin oranı (%22 / %12) — mesafeden
  bağımsız


---

## ADR-010 — Sıradaki kalite adımı: DeepWarp modeli (MVP 7), maske iyileştirmesi değil

**Status:** Accepted · 2026-09-01

### Context
İki bağımsız gözlem aynı tavanı gösterdi: kullanıcı canlı testte, Gemini/Antigravity de
analizinde, gain yükseltilince **iris'te çift görüntü/bulanıklık** olduğunu saptadı.
EXP-005'te maske + rijit taşımaya geçilmiş, hayalet azalmış ama tavan kalkmamıştı.

Alternatif olarak "daha iyi maske + radyal deformasyon" (MVP 3 cilası) önerildi.

### Decision
Sıradaki iş **MVP 7 — DeepWarp modelinin entegrasyonu**. Maske/warp cilası yapılmayacak.

### Reason
2D piksel bükmenin sorunu maskeleme değil, **bilgi eksikliği**: iris kenara kaydığında
arkasında görünmesi gereken sklera dokusu karede hiç yok. Hiçbir maske veya deformasyon
profili var olmayan pikseli üretemez — ancak öğrenilmiş bir model sentezleyebilir.
DeepWarp tam bunun için eğitilmiş (akış alanı + ışık düzeltme modülü).

Üç şey bu adımı bugün mümkün kılıyor:
1. **Ağırlıklar elimizde** (EXP-006) — `models/deepwarp/weights/warping_model/flx/12/{L,R}`
2. **ONNX Runtime zaten projede** (ADR-002) — CoreML dönüşümüne gerek yok, TF1 → ONNX yeter
3. **Model iris landmark'ı istemiyor** — girdileri: 48×64 göz kırpması, 6 göz kontur
   noktasından üretilen 12 kanallı anchor map, ve gözler arası mesafeden hesaplanan
   düzeltme açısı. Yani mevcut `GazeGeometry3D` ve göz konturlarıyla doğrudan besleniyor.

### Alternatives
- *MVP 3 cilası (maske/radyal deformasyon)* — aynı tavana çarpar, zaman kaybı
- *MVP 5 sanal kamera önce* — ürünü görünür kılar ama kötü görüntüyü Zoom'a taşır;
  kalite döngüsü çok yavaşlar

### Consequences
- Risk TF1 checkpoint → ONNX dönüşümünde, özellikle `spatial_transform.py`'daki özel
  bilinear örnekleme katmanında. **Bu yüzden ilk adım Swift'e dokunmadan Python'da
  sayısal doğrulama** (aynı girdi → TF ve ONNX çıktıları karşılaştırılır).
- Geometrik warp fallback olarak korunur; model yüklenemezse ona düşülür.
