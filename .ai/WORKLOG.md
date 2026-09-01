# Worklog

Tamamlanmış anlamlı çalışmalar. En yeni üstte.

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
