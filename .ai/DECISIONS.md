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

## ADR-002 — macOS'ta MediaPipe çalıştırma yolu

**Status:** ⚠️ **Open — karar verilmedi** · 2026-08-29

### Context
MediaPipe Tasks'ın resmî Swift dağıtımı (`MediaPipeTasksVision` CocoaPod) **iOS'u
hedefler.** macOS için hazır bir prebuilt paket bilinmiyor. ADR-001 uygulanabilmesi için
bu sorunun cevaplanması gerekiyor.

### Decision
**Henüz verilmedi.** MVP 2'nin ilk işi bir teknik sondaj (spike): macOS'ta tek bir kareyi
Face Landmarker'dan geçirip 478 nokta almak.

### Alternatives

| Seçenek | Artı | Eksi |
|---|---|---|
| MediaPipe C API'sini Bazel ile macOS için derlemek | Resmî pipeline, tam özellik | Bazel zinciri ağır, CI'da acı |
| Alttaki TFLite modellerini doğrudan çalıştırmak (LiteRT) | Az bağımlılık | Yüz tespit → landmark hattını elle kurmak gerekir |
| ONNX'e çevirip ONNX Runtime ile çalıştırmak | Windows ile aynı runtime | Dönüşüm doğruluğu test edilmeli |
| Apple Vision + yalnız iris için ikinci model | En az iş | İki sistem, karmaşa, ADR-001'in amacını zayıflatır |

### Reason
Seçim, sondajda hangisinin gerçekten çalıştığına göre yapılacak. Masa başında karar
vermek için yeterli bilgi yok — **TODO: verify.**

### Consequences
Bu karar `core/` klasörünün dilini de belirleyecek (ADR-004). MediaPipe'ı zaten C++ olarak
bağlıyorsak paylaşılan çekirdeği de C++ yazmak doğal seçim olur.

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
