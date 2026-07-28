#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetWorkingDir A_ScriptDir
CoordMode("Caret", "Screen")
CoordMode("Mouse", "Screen")

; ============================================================
;  Lang-Guard v2 - Hebrew/English wrong-layout typing detector
;  Watches what you type. If it looks like you forgot to switch
;  the keyboard language, a bubble pops up near the caret:
;     F10 (or click)  = fix ALL the wrong words AND switch layout
;     Esc / click elsewhere = dismiss
;  F10 also works any time on the words just typed (LangOver-style).
; ============================================================

; ---------- config ----------
VERSION := "1.3.2"
;@Ahk2Exe-SetVersion %A_PriorLine~U)^(.+"){1}(.+)".*$~$2%
;@Ahk2Exe-SetProductName Lang-Guard
;@Ahk2Exe-SetDescription Lang-Guard - Hebrew/English wrong-layout typing fixer
;@Ahk2Exe-SetCompanyName Holy Estates
UPDATE_BASE := "https://raw.githubusercontent.com/yakov-design/lang-guard/main/latest"
MIN_HE2EN := 3        ; min length to flag Hebrew-typed text that spells an English word
MIN_EN2HE := 4        ; min length to flag English-typed text that is not an English word
BUBBLE_MS := 8000     ; bubble auto-hide
MAX_RUN   := 20       ; how many recent words to remember for multi-word fixing

OnError(LogError)
LogError(e, mode) {
    try FileAppend(A_Now "  " e.Message " @ " e.File ":" e.Line "`n", A_ScriptDir "\error.log")
    return 1
}

; ---------- first-run self-install (lets people just download the exe from GitHub) ----------
InstallSelf()
InstallSelf() {
    dest := EnvGet("LOCALAPPDATA") "\Lang-Guard"
    if !A_IsCompiled || A_ScriptDir = dest
        return
    r := MsgBox("Install Lang-Guard so it starts automatically with Windows?`n`nYes = install + auto-start (recommended)`nNo = just run it this once", "Lang-Guard", "YesNo Iconi")
    if r != "Yes"
        return
    DirCreate(dest)
    try {
        FileCopy(A_ScriptFullPath, dest "\LangGuard.exe", 1)
    } catch {   ; target exe is locked = already installed and running
        MsgBox("Lang-Guard is already installed and running on this computer.", "Lang-Guard", "Iconi T5")
        ExitApp
    }
    FileCreateShortcut(dest "\LangGuard.exe", A_Startup "\Lang-Guard.lnk",,, "Lang-Guard HE/EN wrong-layout detector")
    Run('"' dest '\LangGuard.exe"')
    ExitApp
}

; ---------- layout maps (standard SI-1452 Hebrew) ----------
en2he := Map(
    "q","/", "w","'", "e","ק", "r","ר", "t","א", "y","ט", "u","ו", "i","ן", "o","ם", "p","פ",
    "a","ש", "s","ד", "d","ג", "f","כ", "g","ע", "h","י", "j","ח", "k","ל", "l","ך", ";","ף", "'",",",
    "z","ז", "x","ס", "c","ב", "v","ה", "b","נ", "n","מ", "m","צ", ",","ת", ".","ץ", "/",".")
he2en := Map()
for k, v in en2he
    he2en[v] := k

; ---------- dictionaries (FileInstall embeds them when compiled to .exe) ----------
dictDir := A_Temp "\Lang-Guard"
DirCreate(dictDir)
FileInstall("common_english.txt", dictDir "\common_english.txt", 1)
FileInstall("all_english.txt", dictDir "\all_english.txt", 1)
common := LoadDict(dictDir "\common_english.txt")   ; ~10k frequent words: "is this English?"
allEng := LoadDict(dictDir "\all_english.txt")      ; ~370k words: "is this NOT English?"

LoadDict(f) {
    d := Map()
    d.CaseSense := false
    Loop Read f {
        line := Trim(A_LoopReadLine)
        if line != ""
            d[line] := 1
    }
    return d
}

; ---------- state ----------
buf := ""             ; current word being typed
wordRun := []         ; recent words this burst: {typed, hadSpace, pad}
pending := 0          ; {dir} while a bubble is up
bubble := 0
paused := false
soundOn := true
dismissed := Map()    ; words the user dismissed - don't nag again this session

; ---------- tray ----------
A_IconTip := "Lang-Guard - HE/EN layout watcher"
A_TrayMenu.Insert("1&", "Pause detection", TogglePause)
A_TrayMenu.Insert("2&", "Sound", ToggleSound)
A_TrayMenu.Check("Sound")
TogglePause(*) {
    global paused
    paused := !paused
    A_TrayMenu.ToggleCheck("Pause detection")
    TrayTip("Lang-Guard", paused ? "Detection paused" : "Detection resumed")
}
ToggleSound(*) {
    global soundOn
    soundOn := !soundOn
    A_TrayMenu.ToggleCheck("Sound")
}

; ---------- keyboard hook ----------
ih := InputHook("V")
ih.OnChar := CharTyped
ih.KeyOpt("{Backspace}{Enter}{NumpadEnter}{Tab}{Escape}{Left}{Right}{Up}{Down}{Home}{End}{Delete}{PgUp}{PgDn}", "N")
ih.OnKeyDown := KeyPressed
ih.Start()

CharTyped(ih, ch) {
    global buf, paused
    if paused
        return
    if (ch = " ") {
        WordDone(true)
        return
    }
    if (Ord(ch) < 32)   ; control chars
        return
    buf .= ch
}

KeyPressed(ih, vk, sc) {
    global buf
    key := GetKeyName(Format("vk{:X}", vk))
    switch key {
        case "Backspace":
            buf := SubStr(buf, 1, -1)
        case "Enter", "NumpadEnter", "Tab":
            ResetState()   ; text likely submitted / caret moved - can't fix across it
        default:           ; arrows / Home / End / Delete / Escape - caret moved
            ResetState()
    }
}

~LButton:: {
    global bubble
    MouseGetPos(,, &win)
    if IsObject(bubble) && win = bubble.Hwnd
        return              ; clicking the bubble itself
    ResetState()
}

ResetState() {
    global buf, wordRun
    buf := ""
    wordRun := []
    HideBubble()
}

; ---------- word tracking + detection ----------
WordDone(hadSpace) {
    global buf, wordRun, pending, dismissed, MAX_RUN
    w := buf
    buf := ""
    if w = "" {
        if wordRun.Length          ; extra space - remember it for accurate backspacing
            wordRun[wordRun.Length].pad += 1
        return
    }
    wordRun.Push({typed: w, hadSpace: hadSpace, pad: 0})
    if wordRun.Length > MAX_RUN
        wordRun.RemoveAt(1)
    if dismissed.Has(w)
        return
    dir := FlagWord(w)
    if dir
        ShowBubble(dir)
    else if IsObject(pending)
        ShowBubble(pending.dir)   ; refresh preview/timer while user keeps typing
}

; returns "he"/"en" if this word alone is strong evidence of wrong layout, else ""
FlagWord(w) {
    global he2en, common, allEng, MIN_HE2EN, MIN_EN2HE
    ; typed with the HEBREW layout, keys spell a common English word
    if RegExMatch(w, "^[\x{05D0}-\x{05EA}',./]+$") && RegExMatch(w, "[\x{05D0}-\x{05EA}]") {
        conv := MapWord(w, he2en)
        if conv != "" {
            core := RegExReplace(conv, "^[.,;'/]+|[.,;'/]+$")
            if StrLen(core) >= MIN_HE2EN && common.Has(StrLower(core))
                return "en"
        }
    }
    ; typed with the ENGLISH layout, not an English word (edge punctuation maps to Hebrew letters)
    else if RegExMatch(w, "^[',./]*[a-z]+[',./]*$") {
        core := RegExReplace(w, "^[',./]+|[',./]+$")
        if StrLen(w) >= MIN_EN2HE && !allEng.Has(core) && !InStr(w, "q") && !InStr(w, "w") {
            conv := MapWord(w, en2he)
            if conv != "" && ValidHebrew(conv) && !NearEnglish(core)
                return "he"
        }
    }
    return ""
}

; structurally possible Hebrew? final letters (םןץףך) only at the end, no regular מנצפכ at the end
ValidHebrew(h) {
    core := RegExReplace(h, "[^\x{05D0}-\x{05EA}]+$", "")
    if core = ""
        return false
    if StrLen(core) > 1 && RegExMatch(SubStr(core, 1, -1), "[םןץףך]")
        return false
    if RegExMatch(SubStr(core, -1), "[מנצפכ]")
        return false
    return true
}

; within one edit (typo distance) of a common English word?
NearEnglish(w) {
    global common
    n := StrLen(w)
    if n < 3
        return false
    letters := "abcdefghijklmnopqrstuvwxyz"
    Loop n {
        i := A_Index
        if common.Has(SubStr(w, 1, i-1) SubStr(w, i+1))          ; deletion
            return true
        if i < n {                                                ; transposition
            t := SubStr(w, 1, i-1) SubStr(w, i+1, 1) SubStr(w, i, 1) SubStr(w, i+2)
            if t != w && common.Has(t)
                return true
        }
    }
    Loop n {
        i := A_Index
        Loop Parse letters {                                      ; substitution
            s := SubStr(w, 1, i-1) A_LoopField SubStr(w, i+1)
            if s != w && common.Has(s)
                return true
        }
    }
    Loop n + 1 {
        i := A_Index
        Loop Parse letters {                                      ; insertion
            if common.Has(SubStr(w, 1, i-1) A_LoopField SubStr(w, i))
                return true
        }
    }
    return false
}

; can this word plausibly be converted in the given direction? "" = stop the walk-back
ConvertFor(dir, w) {
    global he2en, en2he, allEng
    if dir = "he" {
        lw := StrLower(w)
        if !RegExMatch(lw, "^[',./]*[a-z]+[',./]*$")
            return ""
        core := RegExReplace(lw, "^[',./]+|[',./]+$")
        if StrLen(core) >= 3 && allEng.Has(core)
            return ""                     ; clearly real English - stop here
        conv := MapWord(lw, en2he)
        if conv != "" && StrLen(core) > 2 && !ValidHebrew(conv)
            return ""                     ; can't be Hebrew (final letters misplaced)
        return conv
    } else {
        if !RegExMatch(w, "^[\x{05D0}-\x{05EA}',./]+$") || !RegExMatch(w, "[\x{05D0}-\x{05EA}]")
            return ""
        conv := MapWord(w, he2en)
        if conv = ""
            return ""
        core := RegExReplace(conv, "^[.,;'/]+|[.,;'/]+$")
        if StrLen(core) >= 3 && !allEng.Has(core)
            return ""                     ; clearly real Hebrew - stop here
        return conv
    }
}

MapWord(w, m) {
    out := ""
    Loop Parse w {
        if !m.Has(A_LoopField)
            return ""
        out .= m[A_LoopField]
    }
    return out
}

; walk back over the recent words, newest first, until a clearly-correct word
BuildFix(dir) {
    global wordRun
    words := []
    i := wordRun.Length
    while i >= 1 {
        conv := ConvertFor(dir, wordRun[i].typed)
        if conv = ""
            break
        words.InsertAt(1, {rec: wordRun[i], conv: conv})
        i--
    }
    return words
}

Spaces(n) {
    return n > 0 ? Format("{:" n "}", "") : ""
}

; ---------- bubble ----------
ShowBubble(dir) {
    global bubble, pending, BUBBLE_MS, soundOn
    fix := BuildFix(dir)
    if !fix.Length
        return
    preview := ""
    for fw in fix
        preview .= (preview = "" ? "" : " ") fw.conv
    if StrLen(preview) > 45
        preview := SubStr(preview, 1, 45) "..."
    hadBubble := IsObject(bubble)
    HideBubble()
    pending := {dir: dir}
    bubble := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +Border")  ; E0x08000000 = never steals focus
    bubble.BackColor := "C2902C"   ; Holy Estates gold
    bubble.MarginX := 16
    bubble.MarginY := 12
    bubble.SetFont("s13 bold cWhite", "Segoe UI")
    bubble.AddText(, dir = "he" ? "התכוונת לעברית?" : "Did you mean English?")
    bubble.SetFont("s12 norm cFFF3D6", "Segoe UI")
    bubble.AddText("xm", preview)
    bubble.SetFont("s10 norm cDefault", "Segoe UI")
    fixBtn := bubble.AddButton("xm w170 h32", dir = "he" ? "החלף ותקן  (F10)" : "Switch && fix  (F10)")
    fixBtn.OnEvent("Click", (*) => ApplyFix())
    dis := bubble.AddButton("x+10 w110 h32", "Dismiss (Esc)")
    dis.OnEvent("Click", (*) => DismissBubble())
    GetTypingPos(&x, &y, &topY)
    bubble.Show("Hide")                       ; create first to learn its size
    WinGetPos(,, &bw, &bh, bubble.Hwnd)
    wl := 0, wt := 0, wr := A_ScreenWidth, wb := A_ScreenHeight
    try {
        Loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &ml, &mt, &mr, &mb)
            if (x >= ml && x < mr && y >= mt && y < mb) {
                wl := ml, wt := mt, wr := mr, wb := mb
                break
            }
        }
    }
    if x + bw > wr
        x := wr - bw - 8
    if x < wl
        x := wl + 8
    if y + bh > wb                            ; no room below - flip above the field/caret
        y := topY - bh - 10
    if y < wt
        y := wt + 8
    bubble.Show(Format("x{} y{} NoActivate", x, y))
    if soundOn && !hadBubble
        SoundPlay("*48")
    SetTimer(HideBubble, 0)
    SetTimer(HideBubble, -BUBBLE_MS)
}

; best-effort screen position of the text caret; topY = top of the anchor (for flipping above)
GetTypingPos(&x, &y, &topY) {
    x := "", y := "", topY := ""
    if CaretGetPos(&cx, &cy) && (cx || cy) {
        x := cx + 10, y := cy + 30, topY := cy - 8
        return
    }
    ; focused control's rectangle (safe, no COM) - good when the text field is small
    try {
        hwnd := ControlGetFocus("A")
        if hwnd {
            rect := Buffer(16, 0)
            if DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect) {
                l := NumGet(rect, 0, "Int"), t := NumGet(rect, 4, "Int")
                b := NumGet(rect, 12, "Int")
                if (b - t) < 220 {          ; small field: show just below it
                    x := l + 12, y := b + 8, topY := t - 8
                    return
                }
            }
        }
    }
    MouseGetPos(&mx, &my)
    x := mx + 10, y := my + 24, topY := my - 8
}

DismissBubble(*) {
    global pending, dismissed, wordRun
    if IsObject(pending) && wordRun.Length
        dismissed[wordRun[wordRun.Length].typed] := 1
    HideBubble()
}

HideBubble(*) {
    global bubble, pending
    if IsObject(bubble) {
        bubble.Destroy()
        bubble := 0
    }
    pending := 0
}

; ---------- fixing ----------
ApplyFix() {
    global pending, wordRun
    if !IsObject(pending)
        return
    dir := pending.dir
    HideBubble()
    fix := BuildFix(dir)
    if !fix.Length
        return
    n := 0
    text := ""
    for j, fw in fix {
        n += StrLen(fw.rec.typed)
        text .= fw.conv
        if j < fix.Length {
            n += 1 + fw.rec.pad
            text .= Spaces(1 + fw.rec.pad)
        }
    }
    last := fix[fix.Length]
    if last.rec.hadSpace {
        n += 1 + last.rec.pad
        text .= Spaces(1 + last.rec.pad)
    }
    Send("{BS " n "}")
    SendText(text)
    SwitchLayout(dir = "he" ? "0000040d" : "00000409")
    wordRun := []
}

SwitchLayout(klid) {
    hkl := DllCall("LoadKeyboardLayout", "Str", klid, "UInt", 1, "Ptr")
    ; WM_INPUTLANGCHANGEREQUEST - target the focused control; fall back to the window
    focused := 0
    try focused := ControlGetFocus("A")
    if focused
        PostMessage(0x50, 0, hkl, focused)
    else
        PostMessage(0x50, 0, hkl, , "A")
}

; F10 = apply the bubble's fix, or manually convert the recent words (LangOver-style)
F10:: {
    global pending, buf, wordRun
    if IsObject(pending) {
        ApplyFix()
        return
    }
    if buf != "" {
        wordRun.Push({typed: buf, hadSpace: false, pad: 0})
        buf := ""
    }
    if !wordRun.Length
        return
    lastTyped := wordRun[wordRun.Length].typed
    dir := RegExMatch(lastTyped, "[\x{05D0}-\x{05EA}]") ? "en" : "he"
    pending := {dir: dir}
    ApplyFix()
}

; ---------- self-update (compiled exe only) ----------
if A_IsCompiled {
    try FileDelete(A_ScriptFullPath ".old")      ; leftover from a previous update
    SetTimer(CheckUpdate, 6 * 3600 * 1000)       ; re-check every 6 hours
    SetTimer(() => CheckUpdate(), -30000)        ; first check 30s after start
}

CheckUpdate() {
    global VERSION, UPDATE_BASE
    if !A_IsCompiled
        return
    tmp := A_Temp "\Lang-Guard"
    DirCreate(tmp)
    try {
        Download(UPDATE_BASE "/version.txt?nocache=" A_Now, tmp "\version.txt")
        latest := Trim(FileRead(tmp "\version.txt"))
        if latest = "" || latest = VERSION || !RegExMatch(latest, "^[\d.]+$")
            return
        newExe := tmp "\LangGuard-" latest ".exe"
        Download(UPDATE_BASE "/LangGuard.exe?nocache=" A_Now, newExe)
        if FileGetSize(newExe) < 1000000       ; sanity: a real build is several MB
            return
        old := A_ScriptFullPath ".old"
        try FileDelete(old)
        FileMove(A_ScriptFullPath, old, 1)     ; a running exe can be renamed, not overwritten
        FileCopy(newExe, A_ScriptFullPath, 1)
        TrayTip("Lang-Guard", "Updated to v" latest)
        Run('"' A_ScriptFullPath '"')
        ExitApp
    }
}

TrayTip("Lang-Guard", "Watching for wrong-language typing. F10 fixes what you just typed. (v" VERSION ")")
