; WinKey shortcuts
^!1::runDiffConsole(1)
^!2::runDiffConsole(2)
^!3::runDiffConsole(3)
^!4::FileRemoveDir, C:\temp\clipboard-log, 1

; Chrome: Ctrl+W deletes previous word like Vim (close tabs with Ctrl+F4 instead)
; Chrome: Ctrl+S erases the whole current line (save page with Ctrl+P > Save as PDF, or menu)
#IfWinActive ahk_exe chrome.exe
^w::Send, ^{Backspace}
^s::Send, {Home}+{End}{Del}
#IfWinActive

; Services
#Persistent 
OnClipboardChange:
IfNotExist, C:\temp\clipboard-log
  FileCreateDir, C:\temp\clipboard-log
FileAppend, -------------------------------------------------------`n%clipboard%`n, C:\temp\clipboard-log\dump.txt
return

; Methods
runDiffConsole(x) {
    Run, quickdiff.exe %x%
}
