; WinKey shortcuts
^!1::runDiffConsole(1)
^!2::runDiffConsole(2)
^!3::runDiffConsole(3)
^!4::FileRemoveDir, C:\temp\clipboard-log, 1

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
