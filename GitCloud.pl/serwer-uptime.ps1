$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptime = (Get-Date) - $boot
$txt = "Uptime: {0}d {1}h {2}m {3}s" -f $uptime.Days, $uptime.Hours, $uptime.Minutes, $uptime.Seconds

$txt | Set-Content "C:\Windows\database\login\serwer-uptime.txt" -Encoding UTF8

$txt
