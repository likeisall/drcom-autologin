' ============================================================
'  Campus Network Auto-Login - hidden launcher
'  Called by the Startup shortcut. Starts campus-login.ps1
'  in daemon mode with NO visible console window.
'
'  NOTE: comments are kept in English on purpose, because VBS
'  files are parsed as ANSI and non-ASCII text may garble.
' ============================================================
Option Explicit

Dim sh, fso, baseDir, ps1Path, pwshPath, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = baseDir & "\campus-login.ps1"

' Prefer PowerShell 7 (Store alias), fall back to the versioned path.
pwshPath = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\pwsh.exe"
If Not fso.FileExists(pwshPath) Then
    pwshPath = "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.6.0_x64__8wekyb3d8bbwe\pwsh.exe"
End If
If Not fso.FileExists(pwshPath) Then
    pwshPath = "powershell.exe"
End If

cmd = """" & pwshPath & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & ps1Path & """"

' 0 = hidden window, False = do not wait for it to finish
sh.Run cmd, 0, False
