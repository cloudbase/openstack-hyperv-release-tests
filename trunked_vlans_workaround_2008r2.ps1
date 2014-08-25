$ErrorActionPreference = "Stop"

$ns = "root\virtualization"

$sw = gwmi -Namespace $ns -class "Msvm_virtualswitch" -Filter "ElementName = 'external'"
$swports = gwmi -Namespace $ns -q "associators of {$sw} where ResultClass=Msvm_SwitchPort"
foreach($swport in $swports) {
    $swleps = gwmi -Namespace $ns -q "associators of {$swport} where ResultClass=Msvm_SwitchLanEndPoint"
    if($swleps) {
        foreach($swlep in $swleps) {
            $eeps = gwmi -Namespace $ns -q "associators of {$swlep} where ResultClass=Msvm_ExternalEthernetPort"
            if($eeps) {
                $vlanep = gwmi -Namespace $ns -q "associators of {$swport} where assocClass=MSVM_Bindsto"
                if ($vlanep.DesiredEndpointMode -ne 5 ) {
                    $vlanep.DesiredEndpointMode = 5
                    $vlanep.Put()
                }                
                $vlanep= gwmi -Namespace $ns -q "associators of {$vlanep} where ResultClass=Msvm_VLANEndpointSettingData"                
                $vlanep.TrunkedVLANList = @()
                for ($i=500; $i -le 2000; $i++) { 
                    $vlanep.TrunkedVLANList += $i
                }
                $vlanep.Put()                
            }
        }
    }
}