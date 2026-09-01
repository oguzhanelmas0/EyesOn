# Current Task

**Son güncelleme:** 2026-08-29 · **Agent:** Claude (Opus 5)

## Goal

MVP 0'ı tamamlamak: repository tabanlı AI çalışma hafızası + teknik dokümantasyon
altyapısını kurmak, ve proje dosya hiyerarşisini çok platformlu geliştirmeye uygun
hale getirmek.

Bu görev **kod değişikliği içermez.** Mevcut görüntü işleme algoritması ve Swift kodu
kasıtlı olarak ellenmemiştir.

## User-visible Result

Kullanıcı Claude / Codex / Gemini arasında geçiş yaparken projeyi baştan anlatmak
zorunda kalmaz. Yeni agent `AGENTS.md` → `.ai/CURRENT_TASK.md` → `git diff` sırasını
izleyerek birkaç dakikada devralır.

## Current Pipeline Context

Pipeline aşamalarının hiçbiri. Bu bir altyapı/dokümantasyon görevidir.

## Current State

Tamamlandı:

- Yerel proje `github.com/oguzhanelmas0/EyesOn` reposuna bağlandı (`main` takip ediyor)
- Xcode projesi kökten `apps/macos/` altına taşındı (git mv ile, geçmiş korunarak)
- `Examples/` (4.9 GB) `.gitignore`'a alındı; içindeki gerçekten değerli iki proje
  `reference/` altına kopyalandı ve git'e girdi
- `AGENTS.md`, `CLAUDE.md`, `.ai/`, `docs/` yazıldı

## Plan

- [x] Repoya bağlan, `.gitignore` düzenle (Examples/, `._*`)
- [x] Dosya hiyerarşisini kur (`apps/`, `docs/`, `core/`, `models/`, `reference/`)
- [x] `Examples/`'tan referans kodu `reference/`'a kopyala
- [x] `AGENTS.md` + `CLAUDE.md`
- [x] `.ai/` hafıza dosyaları
- [x] `docs/` teknik dokümantasyon
- [x] MVP planı ([docs/ROADMAP.md](../docs/ROADMAP.md))
- [ ] Kullanıcı onayı sonrası commit + push

## Progress

Doküman altyapısı yazıldı, commit edilmedi. Commit ve push kullanıcı onayı bekliyor.

## Files Involved

`AGENTS.md`, `CLAUDE.md`, `README.md`, `.gitignore`,
`.ai/*`, `docs/*`, `reference/*`, `core/README.md`, `models/README.md`

Kod dosyalarında **hiçbir değişiklik yapılmadı** — yalnızca `apps/macos/` altına taşındılar.

## Current Focus

Doküman seti tamamlandı. Sıradaki adım kullanıcının hiyerarşiyi onaylaması ve
MVP 1'e geçilmesi.

## Experiments Tried

Yok — bu görev deney içermiyor.

## Results

Ölçüm yok (kod değişmedi).

## Known Problems

Bu görevden kaynaklanan bilinen problem yok. Kodun kendisindeki bilinen problemler
[docs/EYE_CONTACT.md](../docs/EYE_CONTACT.md#bilinen-kod-problemleri) altında listelendi.

⚠️ **Doğrulanmadı:** Xcode projesi taşındıktan sonra **derlenmedi.** `objectVersion 77`
(Xcode 16 senkronize klasör grupları) kullanıldığı ve `project.pbxproj` içinde mutlak
yol bulunmadığı için taşımanın güvenli olduğu değerlendirildi, ancak bu bir kod okuması
sonucudur, derleme testi değildir. **MVP 1'in ilk işi projeyi Xcode'da açıp derlemektir.**

## Do Not Change

- `apps/macos/EyesOn/` içindeki Swift/Metal kaynak kodu — bu görev kapsamında dokunulmadı
- `reference/` altındaki Python kodu — referans amaçlı, olduğu gibi korunur

## Next Action

**MVP 1'e başla.** İlk somut işlem:

1. `apps/macos/EyesOn.xcodeproj`'i Xcode'da aç, derle, çalıştır — taşımanın bozmadığını doğrula
2. Uygulamada "⚡ Düzeltme" toggle'ını aç ve düzeltmenin gerçekte ne yaptığını gözlemle
   (ekran görüntüsü/kayıt al — baseline olarak `.ai/EXPERIMENTS.md`'ye EXP-001 olarak gir)
3. Bulguları [docs/EYE_CONTACT.md](../docs/EYE_CONTACT.md) içine işle

Detay: [docs/ROADMAP.md](../docs/ROADMAP.md#mvp-1--temel-doğrulama--kamera-io)
