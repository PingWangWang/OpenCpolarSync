' AutoStart.vbs — Auto-start openlist service silently (no admin required)
' Usage: Place a shortcut of this file into shell:startup (Win+R, type shell:startup)

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

' Auto-detect script directory (no hardcoded paths)
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Build path to openlist.exe
exeFile = fso.BuildPath(scriptDir, "openlist.exe")

If Not fso.FileExists(exeFile) Then
    MsgBox "Cannot find openlist.exe. Make sure AutoStart.vbs is placed in the Openlist directory.", vbExclamation, "OpenList Auto-Start"
    WScript.Quit 1
End If

' Launch openlist.exe server hidden, working directory set to script location
shell.Run """" & exeFile & """ server", 0, False
