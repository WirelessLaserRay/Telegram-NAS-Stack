Set WshShell = CreateObject("WScript.Shell")
' 以隐藏窗口的形式在后台运行 start_mount.bat
WshShell.Run chr(34) & "start_mount.bat" & Chr(34), 0
Set WshShell = Nothing
