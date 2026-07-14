# Lang-Guard

Catches the classic Hebrew/English mistake: you start typing before switching the keyboard
language and get gibberish (e.g. `akuo kfuko` instead of `שלום לכולם`).

## What it does
- Watches typing system-wide (AutoHotkey v2 keyboard hook — everything stays local, nothing leaves the PC).
- When a word looks like wrong-layout gibberish, a **gold bubble** appears next to the caret (with a sound):
  - **F10** or clicking the button → fixes **all the garbled words in the current burst**,
    retypes them in the intended language, **and switches the keyboard layout**.
  - **Esc**, clicking elsewhere, Dismiss → dismisses (a dismissed word won't nag again this session).
- **F10 also works any time** on what you just typed, even without a bubble (LangOver-style manual fix).

## Multi-word fixing
It remembers the words typed since your last click/arrow/Enter. On fix, it walks backwards
converting each word, stopping at the first word that's clearly correct in its own language
(a real English word, or Hebrew whose key-map isn't English). So "please send akuo kfuko"
only converts the last two words.

## Files
- `LangGuard.ahk` — the tool (AutoHotkey v2). **Reserved-name warning:** `edit`/`run` can't be variable names. **Never edit with PowerShell Set-Content** — it corrupts the Hebrew literals (BOM-less UTF-8 read as ANSI); use a proper editor.
- `common_english.txt` / `all_english.txt` — word lists for detection.
- `Share\` — standalone package for other PCs: `LangGuard.exe` (word lists embedded),
  `Install Lang-Guard.bat` (installs + auto-start), `README.txt`. Zipped as `Lang-Guard-Share.zip`.

## Sharing / installing on another PC
Copy `Lang-Guard-Share.zip`, extract, run `Install Lang-Guard.bat`. No AutoHotkey needed there.
After editing `LangGuard.ahk`, recompile:
`%LOCALAPPDATA%\Programs\AutoHotkey\Compiler\Ahk2Exe.exe /in LangGuard.ahk /out Share\LangGuard.exe /base %LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe`

## Control
- Tray icon → **Pause detection** / **Sound** on-off / Exit.
- This PC currently runs `Share\LangGuard.exe`; auto-start not yet configured here.

## Known limits
- Enter/Tab clears the tracked words (in chat apps the message may already be sent) — the space-triggered bubble usually catches it earlier.
- Rare false bubbles on technical terms not in the dictionary; Dismiss silences that word for the session.
- Simulated keystrokes won't work in elevated/admin windows.

## Tuning
Top of `LangGuard.ahk`: `MIN_HE2EN`, `MIN_EN2HE` (minimum word lengths), `BUBBLE_MS` (bubble time), `MAX_RUN` (words remembered).
