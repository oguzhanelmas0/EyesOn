# Worklog

Tamamlanmış anlamlı çalışmalar. En yeni üstte.

---

## 2026-09-01 — Claude (Opus 5)

### Task
Referans projelerin algoritmalarını Swift'e entegre etmek; ardından MVP 7 — DeepWarp
göz düzeltme modelini boru hattına bağlamak.

### Changed

**Çekirdek katman kuruldu** (`apps/macos/EyesOn/Core/`, kaynak-bağımsız):
`CorrectionConfig`, `FaceGeometry`, `EMAFilter`, `BehaviorFSM`, `IrisGazeEstimator`,
`GazeGeometry3D`, `GazePipeline`, `VisionFaceAdapter`, `DeepWarpModel`.
Referanstan port edilenler: 4 durumlu davranış FSM'i (histerezis + fade),
EMA yumuşatma, iris offset yöntemi (dikey sönüm 0.5), 3B geometri yöntemi
(IPD → derinlik → düzeltme açısı), göz kırpma geometrisi, 12 kanallı anchor map.

**Düzeltme yolu üç kez yeniden yazıldı**, her seferinde canlı testte çıkan bir hatayla:
1. Metal Gaussian kernel, tüm kare + iki göz zincirlenmiş → **tüm kare yayıldı** (EXP-003)
2. Düz tepeli kernel, izole ROI + maske → **hayalet/çift iris** (EXP-005)
3. Rijit taşıma + convex hull maskesi → temiz, ama 2D bükmenin kalite tavanı
4. **DeepWarp modeli** → sentez, tavan aşıldı (EXP-007, EXP-008)

Metal shader tamamen kaldırıldı; görüntü işleme Core Image + ONNX Runtime üzerinden.

**DeepWarp entegrasyonu:** ağırlıklar GitHub Releases'ten indirildi, TF1 → ONNX
çevrildi ve sayısal doğrulandı, Swift'e bağlandı.

**Düzeltilen buglar:** P1 (clamp GPU'ya ulaşmıyordu), P2 (warp tüm kareye
uygulanıyordu), P3 (koordinat matematiği duplike), P4 (ayrık eşik titremesi),
kamera piksel formatı sabitlendi (32BGRA), Swift 6 concurrency uyarısı.

### Result
Uygulama üç düzeltme modunu destekliyor (İris / Geometri / DeepWarp), varsayılan
DeepWarp. Landmark tespiti MediaPipe (Gemini'nin ONNX entegrasyonu üzerine kuruldu).

### Validation
Her adımda derlendi ve çalıştırıldı; ekran görüntüsüyle gözle kontrol edildi.
TF→ONNX dönüşümü sayısal olarak doğrulandı (max fark 2–3×10⁻⁵).
⚠️ **Otomatik test yok, performans ölçümü yok.**

### Performance
**Ölçülmedi.** Boru hattı artık kare başına üç ONNX çıkarımı içeriyor
(1 landmark + 2 göz). FPS etkisi bilinmiyor — bir sonraki önceliklerden.

### Remaining
- Görsel kalite değerlendirmesi (kullanıcı)
- Performans ölçümü ve gerekirse optimizasyon
- P5 (head pose düzeltme vektörüne girmiyor), P6 (aynalama doğrulanmadı),
  P7 (yatay işaret yönü doğrulanmadı)
- MVP 5: sanal kamera

### Notes
Referans kodun *algoritmalarını* port edip *yapısını* port etmemek pahalıya patladı:
EXP-003'teki yayılma hatası, tam da referansın doğru yaptığı ama bizim atladığımız
yerdeydi (ROI'yi izole edip maskeyle harmanlamak). Ders `.ai/EXPERIMENTS.md`'de.

Ayrıca `reference/deepwarp-cam`'in MediaPipe backend'inde bir hata bulundu ve
düzeltildi: göz merkezini göz köşelerinden değil iris noktalarından hesaplıyordu
(kodun kendi TODO'suydu).

---

## 2026-08-29 — Claude (Opus 5)

### Task
MVP 0 — AI collaboration altyapısı, proje hafızası ve teknik dokümantasyon sistemi kurmak;
dosya hiyerarşisini çok platformlu geliştirmeye hazırlamak.

### Changed
- Yerel klasör git reposu haline getirildi ve `github.com/oguzhanelmas0/EyesOn` remote'una
  bağlandı; `main` branch'i `origin/main`'i takip ediyor (6 commit'lik geçmiş yerelde)
- `.gitignore`: `Examples/` (4.9 GB) ve `._*` (exFAT AppleDouble dosyaları) eklendi
- Xcode projesi `git mv` ile kökten `apps/macos/` altına taşındı — dosya geçmişi korundu
- `Examples/gaze-corrector-main` → `reference/gaze-corrector/`
- `Examples/gaze-correction-cam-master` → `reference/deepwarp-cam/`
  (venv, .git ve poetry.lock hariç; ~4900 satır Python + dokümanlar)
- Oluşturulan dosyalar: `AGENTS.md`, `CLAUDE.md`, `README.md`, `.ai/` (5 dosya),
  `docs/` (13 dosya), `core/README.md`, `models/README.md`, `reference/README.md`

### Result
Üç AI aracı arasında sohbet geçmişinden bağımsız devir teslim mümkün hale geldi.
Proje hiyerarşisi Windows/iOS/Android eklendiğinde simetrik kalacak şekilde kuruldu.

### Validation
⚠️ **Kod derlenmedi ve çalıştırılmadı.** Bu görev kod değişikliği içermiyordu; Xcode
projesinin taşınması `project.pbxproj` incelemesiyle güvenli değerlendirildi
(`objectVersion 77` = Xcode 16 senkronize klasör grupları, mutlak yol yok) ama **derleme
ile doğrulanmadı.** MVP 1'in ilk işi bu doğrulamadır.

### Performance
Ölçüm yok — kod değişmedi.

### Remaining
- Commit + push (kullanıcı onayı bekliyor)
- `Examples/` klasörünün silinmesi (kullanıcı kararı; `reference/` artık bağımsız)

### Notes
Bulgular:
- `Examples/EyesOnAI` tamamen boştu — 4.8 GB'ın tamamı Python venv'i, tek commit bile yok.
  Kurulu paketler (torch, torchvision, coremltools) niyeti gösteriyor: "PyTorch modeli →
  CoreML". İçi hiç doldurulmamış.
- `Examples/EyesOn-main` bu repository'nin birebir kopyasıydı — kurtarılacak bir şey yoktu.
- Geriye kalan iki proje gerçekten değerliydi ve `reference/` altına alındı.
