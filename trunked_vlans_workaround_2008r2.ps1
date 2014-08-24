$ErrorActionPreference = "Stop"

$ns = "root\virtualization"
$p = (gwmi -Namespace $ns -class Msvm_VLANEndpointSettingData -Filter "elementname = 'ExternalSwitchPort'")
$p.TrunkedVLANList = @()
for ($i=500; $i -le 2000; $i++) { $p.TrunkedVLANList += $i }
$p.Put()
