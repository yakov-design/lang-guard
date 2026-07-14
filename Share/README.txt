Lang-Guard — fixes Hebrew/English keyboard mix-ups
====================================================

What it does:
  Started typing before switching the keyboard language? (akuo instead of שלום)
  A gold bubble pops up near your cursor asking if you meant the other language.
  Press F10 (or click the button) — it fixes ALL the garbled words you just
  typed AND switches the keyboard language for you.
  F10 also works any time on the last words you typed, even without a bubble.
  Esc or clicking elsewhere dismisses the bubble.

To install on a new computer (easiest way):
  1. Download LangGuard.exe from:
     https://github.com/yakov-design/lang-guard/raw/main/latest/LangGuard.exe
  2. Double-click it and answer "Yes" to install.
     (If Windows shows a blue "Windows protected your PC" screen,
      click "More info" then "Run anyway" — the app is unsigned, not dangerous.)
  3. Done. It runs now, starts automatically with Windows,
     and updates itself when a new version is published.

(Alternative: copy this folder and run "Install Lang-Guard.bat" — same result.)

To pause or close it:
  Right-click the green tray icon (bottom-right, near the clock) —
  Pause detection / Sound on-off / Exit.

To uninstall:
  Exit it from the tray icon, then delete:
    %LOCALAPPDATA%\Lang-Guard
    the "Lang-Guard" shortcut in shell:startup
