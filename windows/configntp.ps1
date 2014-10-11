Set-Service -Name w32time -StartupType Automatic
w32tm.exe /config /manualpeerlist:pool.ntp.org /syncfromflags:MANUAL /update
Restart-Service w32time
