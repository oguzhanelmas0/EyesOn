# ROADMAP — MVP Planı

Proje MVP'lere bölünmüştür. **Her MVP kendi başına doğrulanabilir bir sonuç üretir**;
bir sonrakine ancak öncekinin çıktısı gözle/ölçümle doğrulandıktan sonra geçilir.

Sıra rastgele değildir: **kalite önce, dağıtım sonra.** Sanal kamerayı düzeltme
kalitesinden önce yaparsak, kötü görünen bir düzeltmeyi Zoom içinde debug etmeye
çalışırız — çok yavaş bir geri bildirim döngüsü.

| MVP | Konu | Platform | Durum |
|---|---|---|---|
| 0 | Dokümantasyon + AI hafıza altyapısı | — | ✅ **Tamamlandı** |
| 1 | Temel doğrulama + kamera I/O | macOS | ⬜ Sıradaki |
| 2 | MediaPipe landmark entegrasyonu | macOS | ⬜ |
| 3 | Bakış tahmini + davranış FSM + stabilizasyon | macOS | ⬜ |
| 4 | Göz düzeltme kalitesi | macOS | ⬜ |
| 5 | Virtual Camera | macOS | ⬜ |
| 6 | Paketleme ve dağıtım | macOS | ⬜ |
| 7 | Öğrenilmiş warp modeli | Platform bağımsız | ⬜ |
| 8 | Windows | Windows | ⬜ |
| 9 | iOS / iPadOS | Apple mobil | ⬜ |
| 10 | Android (telefon + tablet) | Android | ⬜ |

---

## MVP 0 — Dokümantasyon + AI hafıza altyapısı ✅

**Sonuç:** Claude / Codex / Gemini arasında sohbet geçmişinden bağımsız devir teslim.

- [x] Repoya bağlanma, `.gitignore` düzeni
- [x] Monorepo hiyerarşisi (`apps/`, `docs/`, `.ai/`, `core/`, `models/`, `reference/`)
- [x] Referans kodun `Examples/`'tan `reference/`'a taşınması
- [x] `AGENTS.md`, `CLAUDE.md`, `.ai/`, `docs/`

---

## MVP 1 — Temel doğrulama + kamera I/O

**Hedef:** Elimizde ne olduğunu **gerçekten** bilmek ve kamera bağımsızlığının temelini
atmak. Bu MVP'nin yarısı ölçüm, yarısı kod.

**Kullanıcıya görünen sonuç:** Kullanıcı hangi kamerayı kullanacağını seçebilir; seçimi
hatırlanır; kamera çıkarılıp takıldığında uygulama çökmez.

### 1a. Doğrulama (kod yazmadan)
- [ ] `apps/macos/EyesOn.xcodeproj`'i Xcode'da aç, derle, çalıştır — taşımanın bozmadığını doğrula
- [ ] "⚡ Düzeltme"yi aç, düzeltmenin gerçekte ne yaptığını gözlemle ve kaydet →
      `.ai/EXPERIMENTS.md` EXP-001 (baseline)
- [ ] Konsolda `[EyeWarpKernel]` çıktısını kontrol et — Metal kernel yükleniyor mu
- [ ] Aynalama ve "Sol/Sağ" etiketlerinin doğruluğunu gözle doğrula (P6)
- [ ] `os_signpost` ekle, Instruments ile aşama başına gecikmeyi ölç → `PERFORMANCE.md`

### 1b. Kamera I/O
- [ ] `AVCaptureDevice.DiscoverySession` ile kamera enumeration
- [ ] Cihaz seçimi arayüzü (dropdown)
- [ ] Seçimin `UserDefaults`'ta kalıcı saklanması
- [ ] Piksel formatını ve aynalamayı **açıkça** ayarla (varsayma)
- [ ] Disconnect/reconnect davranışı (`wasDisconnectedNotification`)
- [ ] `AVCaptureSessionRuntimeError` ele alınması

### 1c. Test altyapısının başlangıcı
- [ ] Xcode'a unit test target'ı ekle
- [ ] `VisionCoordinateMapper` dönüşüm testleri (P3 riskini kilitler)

**Çıkış kriteri:** Uygulama derleniyor, çalışıyor, kamera seçilebiliyor, ve mevcut
düzeltmenin gerçekte ne yaptığı ölçülmüş/kaydedilmiş durumda.

---

## MVP 2 — MediaPipe landmark entegrasyonu

**Hedef:** ADR-001'i uygulamak. Bu MVP'nin başında ADR-002 (macOS'ta MediaPipe nasıl
çalışacak) kapanmalıdır.

**Kullanıcıya görünen sonuç:** Bakış yönü tespiti gözle görülür şekilde daha isabetli;
debug katmanında iris noktaları görünüyor.

- [ ] **Spike:** macOS'ta tek bir kareyi Face Landmarker'dan geçir, 478 nokta al.
      Denenen yolları ve sonuçlarını `.ai/EXPERIMENTS.md`'ye yaz
- [ ] ADR-002'yi kapat, kararı `.ai/DECISIONS.md`'ye yaz
- [ ] Model dosyasını `models/` altına al, indirme talimatını yaz (git'e commit etme)
- [ ] Landmark kaynağını soyutla — `GazeEstimator`, `LandmarkValidator` ve
      `EyeCorrectionProcessor` şu an `VNFaceObservation` tipine sıkı bağlı
- [ ] MediaPipe landmark'larını boru hattına bağla
- [ ] Debug katmanına iris noktalarını ekle
- [ ] Doğrulama kapısı eşiklerini yeni topolojiye göre yeniden ayarla
- [ ] EXP-001 baseline'ıyla karşılaştır — gerçekten iyileşti mi

**Çıkış kriteri:** 478 landmark canlı akışta çalışıyor, iris noktaları görünüyor,
performans bütçesi aşılmamış.

**Risk:** ADR-002 hiçbir seçenek makul maliyetle çalışmazsa ADR-001 yeniden
değerlendirilmelidir. Bu durumda karar `.ai/DECISIONS.md`'ye "Superseded" olarak işlenir.

---

## MVP 3 — Bakış tahmini + davranış FSM + temporal stabilizasyon

**Hedef:** Düzeltmenin *ne zaman* ve *ne kadar* uygulanacağını doğru yapmak.
Warp kalitesine henüz dokunmuyoruz.

**Kullanıcıya görünen sonuç:** Düzeltme artık açılıp kapanarak titremiyor; kullanıcı
notlarına baktığında yumuşakça çekiliyor, geri döndüğünde geri geliyor.

- [ ] İris offset yöntemine geç (Yöntem A) — dikey sönüm 0.5 dahil
- [ ] solvePnP ile head pose (yaw/pitch/roll) — bakış hesabına **dahil et** (P5)
- [ ] Davranış FSM'ini uygula (4 durum, histerezis, fade süreleri)
- [ ] EMA yumuşatma (landmark α=0.6, blend α=0.3) — mod filtresinin yerine
- [ ] Düzeltme gücünü sürekli `blend ∈ [0,1]` ile çarp (ayrık eşik yerine)
- [ ] Debug HUD'a FSM durumu ve blend değeri ekle
- [ ] FSM ve EMA için unit testler
- [ ] İlk test videolarını çek (`baseline_center`, `reading_notes`, `head_turn`, `blinking`)

**Çıkış kriteri:** Test videolarında jitter, flicker ve gaze oscillation gözle
görülmüyor; FSM geçişleri doğru tetikleniyor.

---

## MVP 4 — Göz düzeltme kalitesi

**Hedef:** Warp'ın kendisini doğru ve doğal hale getirmek.

**Kullanıcıya görünen sonuç:** Düzeltilmiş göz doğal görünüyor; kullanıcı kendisi gibi
görünmeye devam ediyor.

- [ ] **P1 bug'ını düzelt** — `maxPixelShift` Metal yoluna geçirilmeli
- [ ] **P2'yi düzelt** — warp'ı göz ROI'sine kırp, tüm kareye uygulama
- [ ] **P3'ü düzelt** — koordinat matematiğini `VisionCoordinateMapper`'da tekilleştir
- [ ] Geometrik warp'ı uygula (3 noktalı affine ve parçalı affine)
- [ ] Convex hull maskesi + Gaussian feather ile harmanlama
- [ ] Mevcut Metal Gaussian warp ile karşılaştır → `.ai/EXPERIMENTS.md`
- [ ] Görsel kalite kontrol listesini geç (uncanny, deformation, identity drift, blink…)
- [ ] Video file test hattını kur (kamera olmadan deterministik test)

**Çıkış kriteri:** Görsel kalite kontrol listesinde takılan madde yok; performans
bütçesi aşılmamış; regresyon karşılaştırması kurulmuş.

---

## MVP 5 — Virtual Camera

**Hedef:** Ürünün gerçekten var olması. Bu MVP bittiğinde EyesOn kullanılabilir.

**Kullanıcıya görünen sonuç:** Zoom'un kamera listesinde "EyesOn" görünüyor ve
seçildiğinde düzeltilmiş görüntü gidiyor.

- [ ] Çıktı sözleşmesini belirle (piksel formatı, çözünürlük, FPS, kaynak yokken davranış)
- [ ] CMIOExtension target'ı oluştur
- [ ] Ana uygulama ↔ extension IPC (XPC / IOSurface)
- [ ] `OSSystemExtensionRequest` ile kurulum akışı + kullanıcı onayı UX'i
- [ ] Entitlement ve imzalama düzenlemeleri
- [ ] Render yolunu değiştir: `NSImage` yerine doğrudan `CVPixelBuffer`
- [ ] Üç iş parçacıklı boru hattına geç (capture / process / output)
- [ ] Uzun süreli kararlılık testi (bellek, kare düşmesi)
- [ ] Konferans uygulaması matrisi: Zoom, Meet, Teams, Discord, FaceTime, QuickTime

**Çıkış kriteri:** En az Zoom, Meet ve FaceTime'da çalışıyor; 30 dakikalık kesintisiz
çalışmada bellek büyümesi yok.

---

## MVP 6 — Paketleme ve dağıtım

**Hedef:** Başka birinin kurabilmesi.

- [ ] Developer ID ile imzalama, notarization
- [ ] Uygulama ikonu, ilk açılış deneyimi (onboarding)
- [ ] Ayarlar: düzeltme gücü, kamera seçimi, açılışta başlat
- [ ] Menü çubuğu simgesi (uygulama arka planda çalışacak)
- [ ] Kaldırma akışı (extension'ın temiz kaldırılması)
- [ ] Dağıtım kanalı kararı (doğrudan indirme / Sparkle güncelleme)

**Çıkış kriteri:** Temiz bir Mac'e kurulup çalışıyor.

---

## MVP 7 — Öğrenilmiş warp modeli

**Hedef:** Kalite sıçraması. Platform bağımsız kazanç — sonraki tüm platformlar
bundan faydalanır.

- [ ] DeepWarp ağırlıklarını bul (orijinal Releases) veya eğitim planı yap
- [ ] TF1 checkpoint → ONNX dönüşümü; `spatial_transform` katmanını doğrula
- [ ] ONNX → CoreML dönüşümü
- [ ] Anchor map üretimini Swift'te uygula
- [ ] Warp aşamasını değiştir; geometrik warp'ı fallback olarak koru
- [ ] Aynı test videolarında geometrik vs öğrenilmiş karşılaştırması →
      `.ai/EXPERIMENTS.md`
- [ ] Performans bütçesini yeniden ölç

**Çıkış kriteri:** Öğrenilmiş warp geometrikten görsel olarak daha iyi **ve** bütçe
içinde. Değilse geometrik kalır ve deney "Reject" olarak kaydedilir.

---

## MVP 8 — Windows

**Hedef:** En büyük masaüstü pazarı. Aynı ürün şekli, aynı değer önerisi.

- [ ] `core/` kararını ver (ADR-004 devamı): C++ paylaşılan çekirdek mi, port mu
- [ ] Media Foundation ile capture + cihaz enumeration
- [ ] MediaPipe'ı Windows'ta çalıştır (ONNX Runtime muhtemel)
- [ ] Warp'ı Windows'ta uygula (ONNX Runtime + DirectML, CPU fallback)
- [ ] `MFCreateVirtualCamera` (Win11 22H2+)
- [ ] DirectShow filtresi (Win10 ve eski uygulamalar)
- [ ] UI teknolojisi kararı ve arayüz
- [ ] NVIDIA / iGPU / CPU-only makinelerde performans ölçümü
- [ ] Kurulum paketi

**Çıkış kriteri:** Windows 10 ve 11'de Zoom'da çalışıyor; RTX gerektirmiyor.

---

## MVP 9 — iOS / iPadOS

⚠️ **Önce ürün stratejisi kararı gerekir.** Sanal kamera mümkün değil
([PLATFORM_SUPPORT.md](PLATFORM_SUPPORT.md#ios--ipados)); ürün ya kendi görüşme
uygulamamız ya da bir SDK olacak. Bu karar masaüstü sürümü gerçek kullanıcılarda
denenmeden verilmemelidir.

- [ ] Ürün şekli kararı → `.ai/DECISIONS.md`'ye ADR olarak
- [ ] Çekirdeği iOS'a taşı (AVFoundation macOS'a çok yakın)
- [ ] MediaPipe iOS entegrasyonu (resmî CocoaPod var — macOS'tan **daha kolay**)
- [ ] CoreML ile warp modeli
- [ ] Ön kamera geometrisi: `kamera_offset` telefon/tablet için farklı varsayılanlar
- [ ] Termal kısıtlar ve pil tüketimi ölçümü
- [ ] iPad'de tablet ekran düzeni

---

## MVP 10 — Android (telefon + tablet)

⚠️ iOS ile aynı strateji kısıtı — sanal kamera pratikte mümkün değil.

- [ ] CameraX ile capture
- [ ] MediaPipe Android (resmî AAR — birinci sınıf destek)
- [ ] TFLite + NNAPI / GPU delegate ile warp
- [ ] Cihaz parçalanmışlığı: düşük uçlu cihazlarda performans profili
- [ ] Tablet için `kamera_offset` varsayılanı (kamera genelde kenarda)
- [ ] Play Store dağıtımı veya SDK paketi

---

## MVP tamamlama protokolü

Bir MVP "tamamlandı" denmeden önce:

1. Çıkış kriteri gerçekten sağlandı mı — gözle/ölçümle doğrulanmış olmalı
2. `.ai/WORKLOG.md`'ye giriş yazıldı mı (ne değişti, nasıl doğrulandı, ne kaldı)
3. İlgili `docs/` dosyaları güncellendi mi — özellikle
   [PROJECT.md](PROJECT.md#target-pipeline-status) durum tablosu
4. Alınan kararlar `.ai/DECISIONS.md`'ye işlendi mi
5. Denenen ve reddedilen yaklaşımlar `.ai/EXPERIMENTS.md`'ye yazıldı mı
6. `.ai/CURRENT_TASK.md` bir sonraki MVP'ye göre sıfırlandı mı
