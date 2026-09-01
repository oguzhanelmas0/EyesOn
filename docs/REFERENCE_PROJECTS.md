# REFERENCE_PROJECTS

`reference/` altındaki kod **okumak ve port etmek içindir; derlenmez, çalıştırılmaz,
çağrılmaz.** İkisi de MIT lisanslıdır ve `LICENSE` dosyalarıyla birlikte kopyalanmıştır —
türetilen kodda atıf koruyun.

Bunlar `Examples/` klasöründen damıtıldı; `Examples/` silinecektir ve **hiçbir yerden
referans verilmemelidir** (ADR-005).

---

## `reference/gaze-corrector/` — geometrik yaklaşım

Kaynak: `github.com/dkohn1337/gaze-corrector` · MIT · ~1180 satır Python

Model kullanmayan, tamamen geometrik bir çözüm. MediaPipe iris landmark'larını alır,
iris'i göz merkezine doğru kaydırır, harmanlar.

### Bizim için en değerli parçalar

| Dosya | İçerik | Bizde nereye gidiyor |
|---|---|---|
| **`behavior_fsm.py`** | 4 durumlu davranış makinesi, histerezis, fade süreleri | **MVP 3 — en yüksek değerli parça** |
| `smoothing.py` | EMA filtreleri (landmark α=0.6, blend α=0.3) | MVP 3 |
| `gaze_estimator.py` | İris offset + solvePnP head pose; dikey sönüm 0.5 | MVP 3 |
| `gaze_corrector.py` | Affine ve parçalı affine warp, convex hull + feather blend | MVP 4 |
| `config.py` | Tüm landmark indeksleri ve eşik sabitleri | MVP 2–3 |
| `pipeline.py` | 3 iş parçacıklı, drop-oldest kuyruklu boru hattı | MVP 5 |
| `virtual_camera.py` | `pyvirtualcam` sarmalayıcı (OBS Virtual Camera) | Referans — biz CMIOExtension kullanacağız |
| `face_detector.py` | MediaPipe FaceMesh sarmalayıcı | MVP 2 |
| `ui/tray.py` | macOS menü çubuğu simgesi (rumps) | MVP 6 referansı |

**`behavior_fsm.py` neden bu kadar önemli:** ürünün doğal hissetmesini sağlayan tek en
kritik parça. Kullanıcı gerçekten notlarına bakıyorsa düzeltme çekilmeli. Bu olmadan
uygulama "ölü gözlü ve tuhaf" görünür — ve bu, düzeltmemekten kötüdür.

### Beyan ettiği performans

README'sinde ~14–20 ms/kare (MediaPipe 8–12 ms, gaze 1–2 ms, affine warp 2–3 ms,
blending ~1 ms) diyor, Intel ve Apple Silicon Mac'lerde 30 fps hedefliyor.

⚠️ Bunlar **onların beyanıdır, bizim ölçümümüz değildir.**

---

## `reference/deepwarp-cam/` — öğrenilmiş yaklaşım

Kaynak: `github.com/WangWilly/gaze-correction-cam` · MIT · ~3730 satır Python
Makale: Hsu, Wang, Lei, Chen — *"Look at Me! Correcting Eye Gaze in Live Video
Communication"*, ACM TOMM 15(2), 2019

DeepWarp mimarisiyle öğrenilmiş bir akış alanı (optical flow) üretip göz bölgesini
warp eder, üstüne ışık düzeltmesi uygular.

### Bizim için en değerli parçalar

| Dosya | İçerik | Bizde nereye gidiyor |
|---|---|---|
| **`model_managers/gaze_corrector_v1.py`** | **3B geometri matematiği** — IPD'den göz derinliği, kamera offset'i, düzeltme açısı | MVP 7 (ve kalibrasyon) |
| `tf_models/gaze_corrector_v1/gaze_warp_model.py` | DeepWarp ağ mimarisi (coarse→fine flow + LCM) | MVP 7 |
| `tf_models/gaze_corrector_v1/spatial_transform.py` | Bilinear örneklemeli spatial transformer | MVP 7 — **ONNX dönüşümünde riskli kısım** |
| `tf_models/gaze_corrector_v1/layers.py` | CNN/dense blokları | MVP 7 |
| `displayers/face_predictor.py` | Göz ROI kırpma + **anchor map üretimi** (48×64×12) | MVP 7 |
| `model_managers/user_settings_db.py` | Kalibrasyon ayarlarının SQLite'ta saklanması | MVP 6 referansı |
| `docs/architecture.md` | Kendi mimari dokümanları | Arka plan |
| `docs/orignal_doc.md` | Orijinal makale bilgisi + kalibrasyon yöntemi | MVP 7 |
| `docs/useful_links.md` | İlgili araştırma: GazeFlow, 3DGazeNet | Arka plan |

**3B geometri matematiği neden değerli:** iris offset yöntemi (Yöntem A) kameranın
nerede olduğunu bilmez; 3B yöntem bilir. Kamera ekranın üstünde mi, yanında mı,
kullanıcı ne kadar uzakta — bunlar düzeltme açısını değiştirir. Kalibrasyon istediği
için MVP 3'te kullanmıyoruz ama MVP 7'de kalite tavanını yükseltecek olan budur.

### ⚠️ Ağırlıklar yok

Repo yalnızca **mimariyi** içerir. Eğitilmiş checkpoint dosyaları (`weights/warping_model/
flx/12/L/` ve `.../R/`) orijinal projenin GitHub Releases sayfasından indirilir.
`reference/` içinde **hiçbir model dosyası yoktur** — arandı, yok.

Ayrıca dlib backend'i `shape_predictor_68_face_landmarks.dat` ister; o da yok. Zaten
MediaPipe backend'ini kullanacağız (ADR-001).

---

## Damıtılmış olmayan iki proje

`Examples/` altında iki proje daha vardı ve **kasıtlı olarak kopyalanmadılar:**

| Proje | Neden alınmadı |
|---|---|
| `EyesOnAI` | Tamamen boş. 4.8 GB'ın tamamı Python venv'i (torch, torchvision, coremltools, opencv). Proje kodu hiç yazılmamış, tek commit bile yok. Kurulu paketler niyeti gösteriyor ("PyTorch modeli → CoreML") ama içerik yok |
| `EyesOn-main` | Bu repository'nin birebir kopyası — `diff -r` ile doğrulandı. Kurtarılacak bir şey yoktu |

---

## Üç yaklaşımın karşılaştırması

| | Bizim mevcut kod | `gaze-corrector` | `deepwarp-cam` |
|---|---|---|---|
| Landmark | Apple Vision (kaba pupil) | MediaPipe 478 + iris | dlib 68 **veya** MediaPipe |
| Head pose | Vision yaw/pitch — sadece kapı olarak | solvePnP — hesaba dahil | 3B geometri |
| Bakış tahmini | Pupil offset, 5 ayrık yön | İris offset, sürekli | IPD'den 3B konum → açı |
| Warp | Metal Gaussian kernel | Affine / parçalı affine | Öğrenilmiş akış alanı + LCM |
| Davranış kontrolü | ❌ Yok (ayrık eşik) | ✅ 4 durumlu FSM | ❌ Yok |
| Yumuşatma | 6 karelik mod filtresi | EMA | ❌ Yok |
| Çıktı | Kendi penceresi | OBS Virtual Camera | Kendi penceresi |
| Kalibrasyon | ❌ | ❌ Gerekmez | ✅ Odak/IPD/kamera offset |
| Model gerekir mi | Hayır | Hayır | **Evet** (ağırlıklar yok) |

**Planımız üçünün en iyilerini birleştiriyor:** MediaPipe landmark'ları + FSM ve EMA
(`gaze-corrector`) + 3B geometri ve öğrenilmiş warp (`deepwarp-cam`) + mevcut Metal GPU
hattımız ve doğrulama kapımız.
