$vmname = "DC1"
$vhdpath = "C:\VM\$vmname.vhdx"
$isoPath = "C:\iso\en_windows_server_2012_r2_x64_dvd_2707946.iso"
$vmSwitch = "management"

New-VHD $vhdpath -Dynamic -SizeBytes (16 * 1024 * 1024 * 1024)
$vm = New-VM $vmname -MemoryStartupBytes (2 * 1024 * 1024 * 1024)
$vm | Set-VM -ProcessorCount 2
$vm.NetworkAdapters | Connect-VMNetworkAdapter -SwitchName $vmSwitch
$vm | Add-VMHardDiskDrive -ControllerType IDE -Path $vhdpath
$vm | Add-VMDvdDrive -Path $isopath

$vm | Start-Vm
