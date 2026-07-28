# Lang-Guard — HE/EN Wrong-Layout Typing Detector — PROJECT WIREFRAME

> **Single source of truth.** Read this at the start of every session. Update it at the end of every slice.
> Last updated: 2026-07-28 (parked the SmartScreen decision — see Next slice).

## Overview
Catches typing in the wrong keyboard language (`akuo kfuko` instead of `שלום לכולם`). A gold bubble
pops near the cursor; **F10** (or click) fixes ALL the garbled words just typed AND switches the
keyboard language. F10 also works any time without a bubble. Esc/clicking dismisses.

## Tech + how it runs
- **AutoHotkey v2** script `LangGuard.ahk`, compiled to a standalone `LangGuard.exe` (word lists embedded).
- Installed per-PC at `%LOCALAPPDATA%\Lang-Guard` + Startup shortcut (auto-starts at login).
- **Self-updates** from the public repo **github.com/yakov-design/lang-guard** (checks 30s after start + every 6h).
- Install on any PC = download + run one file:
  `https://github.com/yakov-design/lang-guard/raw/main/latest/LangGuard.exe` (first run offers self-install).

## Shipping a tweak
1. Edit `LangGuard.ahk` (NEVER with PowerShell Set-Content — it corrupts the Hebrew; use a real editor/Claude's Edit tool).
2. Bump `VERSION := "x.y.z"` at the top.
3. Run `Publish-Update.ps1` — compiles, pushes to GitHub, updates this PC; other PCs follow within ~6h.
- Gotchas: `edit`/`run` are reserved AHK names; GitHub's raw CDN caches ~5 min (don't test an update immediately).

## Done (highlights)
- **v1.0–1.2 (2026-07-14)** — detection both directions (dictionary-based), bubble + F10 fix, multi-word
  burst fixing, layout switch, typo filters (impossible-Hebrew shapes, 1-letter-off English words),
  crash fix (removed MSAA caret lookup), bubble clamped to screen + flips above bottom-of-screen fields.
- **v1.3.x (2026-07-15)** — one-link install: exe self-installs + auto-starts on first run;
  re-running when installed says "already installed" (no zombie). Self-update verified end-to-end.

## ⏸ Next slice — PARKED (Yakov will get back to this)
**SmartScreen blocks the download/first run on new PCs** ("Windows protected your PC") because the exe
is unsigned with no reputation. Workaround today: "More info → Run anyway" once per PC.
Decision needed — options on the table:
1. **Lang-Guard unblocks its own downloaded updates** (strip mark-of-the-web on its own exe only, like normal
   auto-updaters. Claude's edit for this was **blocked by the permission classifier** — needs Yakov's explicit
   in-conversation OK, then re-apply to `CheckUpdate()` + `InstallSelf()`).
2. **Submit the exe to Microsoft** as a false positive (free, takes days, helps Defender; SmartScreen
   reputation still builds slowly).
3. **Code-signing certificate** (~$100–400/yr) — the proper fix; warnings disappear for real.
- Current state: **v1.3.1 is live/published**. `LangGuard.ahk` has v1.3.2 staged locally (exe version-info
  metadata: product name/company/version — harmless, makes the file look legitimate) — **not yet published**.
- Risk while parked: after each published update, PCs may show the SmartScreen prompt again at next launch.
  (No updates planned while parked, so quiet in practice.)

## Session log
- **2026-07-14** — built v1 → v1.2.1: detection, bubble, multi-word F10 fix, auto-start (Yakov approved), typo filters. Tested end-to-end via injected-keystroke harness.
- **2026-07-15** — GitHub repo + self-update pipeline + one-link self-install (v1.3.0/1.3.1), both install paths tested.
- **2026-07-28** — Yakov reported Windows blocked the download on another PC (SmartScreen). Metadata prepared (v1.3.2, unpublished); mark-of-the-web auto-unblock blocked by classifier; decision parked to a later session.
