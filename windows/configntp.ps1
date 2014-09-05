Set-Service -Name w32time -StartupType Automatic
w32tm.exe /config /manualpeerlist:pool.ntp.org /syncfromflags:MANUAL /update
net stop w32time
net start w32time
