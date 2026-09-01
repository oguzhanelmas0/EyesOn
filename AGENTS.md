# AGENTS.md — EyesOn

Claude (VS Code), Codex (VS Code) ve Gemini (Antigravity) için ortak çalışma kuralları.
Bu dosya kısa ve yüksek sinyallidir. Detay `docs/` altındadır, canlı durum `.ai/` altındadır.

---

## Project

EyesOn, gerçek zamanlı **eye-contact correction (bakış/göz teması düzeltme)** yapan ve
sonucu bir **virtual camera** olarak sunan bir masaüstü uygulamasıdır. Kullanıcı Zoom,
Google Meet, Teams veya Discord'da toplantıdayken ekrana, notlarına veya başka bir yere
bakıyor olsa da işlenmiş video çıkışında gözleri doğal biçimde kameraya bakıyor görünür.

Aktif geliştirme platformu: **macOS**. Sonraki hedefler: Windows, iOS/iPadOS, Android.

## Core Product Goal

> "Whatever supported physical camera the user selects, capture its video, perform natural
> real-time eye-contact correction, and expose the processed stream as a camera usable by
> conferencing applications."

**Mevcut durumu olduğundan ileri gösterme.** Bugün itibarıyla bu hedefin yalnızca ilk
yarısı kısmen implement edilmiştir: kamera yakalama + yüz/göz tespiti çalışıyor;
göz düzeltmesi deneysel ve varsayılan olarak kapalı; **virtual camera hiç yazılmadı.**
Gerçek durum: [docs/PROJECT.md](docs/PROJECT.md#target-pipeline-status).

## Priorities

Çakışma olduğunda bu sıra geçerlidir:

1. Natural visual quality — fark edilen düzeltme, düzeltmemekten kötüdür
2. Temporal stability — tek frame değil, video akışı iyi görünmeli
3. Low latency
4. Real-time FPS (30 fps hedefi)
5. Identity preservation — kullanıcı kendisi gibi görünmeli
6. Head-pose robustness
7. Eye-region consistency
8. Camera compatibility — üretici/model bağımsızlığı
9. GPU/CPU efficiency
10. Privacy — işleme cihazda kalır

## AI Collaboration Model

Claude, Codex ve Gemini **aynı working tree üzerinde sırayla** çalışır. Bir agent'ın
kullanım limiti dolduğunda diğeri devralır.

Başlayan agent, çalışma ağacındaki değişikliklerin kendisine ait olmadığını varsaymalıdır.
Sohbet geçmişi paylaşılmaz — **tek ortak hafıza bu repository'dir.**

## Resume Protocol

Kullanıcı sadece **"devam et"** dese bile şu sırayı uygula:

1. `.ai/CURRENT_TASK.md` oku — aktif görev ve kalınan nokta
2. `.ai/DECISIONS.md` içinde göreve ilgili ADR'leri oku
3. `git status --short`
4. `git diff --stat`
5. `git diff` — önceki agent'ın yarım bıraktığı işi gör
6. `git log --oneline -10`
7. Değişmiş dosyaları oku
8. Görevle ilgili `docs/` dosyalarını oku
9. `.ai/EXPERIMENTS.md` — aynı yaklaşımı tekrar denemekten kaçın
10. Mevcut testleri/benchmarkları kontrol et (bkz. [docs/TESTING.md](docs/TESTING.md))

**Mevcut işi sıfırdan yeniden yazmak yerine devam ettir.**

## Working Tree Safety

Kesin kurallar:

- Başka agent'ın uncommitted değişikliklerini **silme**
- `git reset --hard` **kullanma**
- Çalışma ağacını kullanıcı izni olmadan temizleme
- Anlamadığın bir değişikliğin önceki agent'a ait olabileceğini varsay
- Reimplementation yapmadan önce mevcut diff'i incele
- Çalışan bir implementasyonu "daha iyi olur" varsayımıyla tamamen yeniden yazma
- Commit ve push yalnızca kullanıcı istediğinde

## Current Task

Aktif göreve başlar başlamaz `.ai/CURRENT_TASK.md` güncellenmelidir — iş bitince değil,
**başlarken.** Amaç: agent'ın limiti aniden dolsa bile bir sonraki agent'ın nerede
kalındığını anlayabilmesi.

## Completion Protocol

Bir özelliği "tamamlandı" ilan etmeden önce projeye uygun doğrulama yap.

⚠️ **Bu projede şu an hiçbir otomatik test veya benchmark altyapısı yoktur.**
Var gibi davranma. Bugün yapılabilecek doğrulama: uygulamayı Xcode'da derleyip çalıştırmak
ve gözle kontrol etmek. Test altyapısı kurulduğunda [docs/TESTING.md](docs/TESTING.md)
güncellenecek ve bu bölüm ona işaret edecek.

Doğrulama yapılmadıysa bunu açıkça söyle: *"derlendi ama çalıştırılmadı"*, *"kod okundu,
çalıştırılmadı"* gibi.

## Performance Rule

Görüntü işleme değişikliklerinde "çalışıyor" yeterli değildir. Mümkün olduğunda ölç:

FPS · per-frame latency · inference latency · preprocessing · postprocessing ·
CPU · GPU · memory

⚠️ **Bugün hiçbir ölçüm yapılmamıştır** — [docs/PERFORMANCE.md](docs/PERFORMANCE.md)
içindeki tüm hücreler "Not measured yet"tir. Sayı uydurma; ölçtüğün değeri hangi
donanımda ölçtüğünü yazarak kaydet.

## Visual Quality Rule

Eye correction'da geometrik doğruluk tek başına yeterli değildir. Her değişiklikten sonra
şunları gözle kontrol et:

uncanny eye appearance · iris/pupil deformation · eyelid artifacts · identity drift ·
face geometry deformation · texture inconsistency · lighting mismatch · eye color changes ·
gaze jitter · frame-to-frame flicker · asymmetrical eyes · blink corruption

## Temporal Rule

**Tek frame iyi görünürken video kötü görünebilir.** Temporal consistency birinci sınıf
gereksinimdir.

Yeni bir yöntemi değerlendirirken şunlara bak: jitter · flicker · gaze oscillation ·
landmark instability · abrupt eye-region changes.

Bir ekran görüntüsünde güzel görünmesi bir yöntemi kabul etmek için yeterli değildir.

## Experimentation Rule

Bu proje deneysel CV/ML geliştirmesi içerir. Yeni bir yöntem denerken:

```
Problem → Baseline measurement → New method → Same test input
        → Performance comparison → Visual comparison → Temporal comparison → Decision
```

Sonucu — **başarısız olsa bile** — `.ai/EXPERIMENTS.md` içine yaz. Amacı: bir sonraki
agent'ın aynı çıkmaz sokağı tekrar denememesi.

## Privacy

Tüm görüntü işleme **cihaz üzerinde, lokal** yapılır. Kamera karesi hiçbir koşulda harici
bir servise gönderilmez. Bu bir mimari kısıttır; bulut çıkarımı tasarım seçeneği değildir.
Bir değişiklik bunu ihlal edecekse önce kullanıcıya sor ve belgele.

## Tool Rules

Repository'de bugün gerçekten mevcut olanlar:

| Araç | Durum | Kural |
|---|---|---|
| Xcode / Swift | ✅ Kullanılıyor | `apps/macos/EyesOn.xcodeproj`, macOS deployment target 26.3, Swift 5.0 |
| Apple Vision | ✅ Kullanılıyor | Şu anki landmark kaynağı; MediaPipe'a geçilecek (ADR-001) |
| Core Image + Metal | ✅ Kullanılıyor | `GaussianEyeWarp.metal` — CIWarpKernel; `default.metallib` bundle'da olmalı |
| AVFoundation | ✅ Kullanılıyor | Kamera yakalama |
| git | ✅ Var | Remote: `github.com/oguzhanelmas0/EyesOn` |
| MediaPipe | ❌ Henüz yok | Planlı (ADR-001); macOS'ta çalıştırma yolu henüz belirsiz (ADR-002) |
| ONNX / CoreML / PyTorch / TensorRT | ❌ Yok | Faz olarak MVP 7'de gündeme gelir |
| pytest / XCTest | ❌ Yok | Test target'ı yok |
| CI | ❌ Yok | — |
| OpenCV / ffmpeg | ❌ Yok | Yalnız `reference/` altındaki Python projelerinde (derlenmez) |

Var olmayan bir aracı varmış gibi kullanma veya belgeleme.

## Klasör haritası

```
EyesOn/
├── AGENTS.md            ← buradasın: ortak kurallar
├── CLAUDE.md            → AGENTS.md
├── .ai/                 → canlı proje hafızası (görev, worklog, kararlar, deneyler)
├── docs/                → konu bazlı teknik dokümantasyon
├── apps/macos/          → Xcode projesi (aktif geliştirme)
├── core/                → platformlar arası paylaşılan çekirdek (henüz boş)
├── models/              → ML model dosyaları (git'e girmez)
├── reference/           → damıtılmış referans projeler (okumak için, MIT, derlenmez)
└── Examples/            → GEÇİCİ, git'te yok, silinecek — REFERANS VERME
```

## Değişmez kurallar

1. **`Examples/` klasörüne asla referans verme.** Geçicidir, silinecektir. İhtiyacın olan
   her şey `reference/` altına kopyalandı.
2. **`reference/` kodu okumak içindir, derlenmez.** Oradan port edilir, çağrılmaz.
   Lisansları MIT; türetilen kodda atıf koru.
3. **Kararları yeniden açma.** `.ai/DECISIONS.md` içindekiler gerekçelidir. Yeni bilgi
   yoksa üzerinden geçme; yeni karar verdiğinde oraya ADR olarak ekle.
4. **Doküman dili Türkçe, kod dili İngilizce.** Commit mesajları Türkçe.
5. **Bu görev kapsamında mevcut çalışan kodu refactor etme.** Doküman ve hafıza
   altyapısı, kod değişikliğinden ayrı tutulur.
