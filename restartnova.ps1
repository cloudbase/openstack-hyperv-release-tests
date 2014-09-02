function Is2012OrAbove() {
    $v = [environment]::OSVersion.Version
    return ($v.Major -ge 6 -and $v.Minor -ge 2)
}

function CheckStopService($serviceName) {
    $s = get-service | where {$_.Name -eq $serviceName}
    if($s -and $s.Status -ne "Stopped") { net stop $serviceName }
}

function CheckStartService($serviceName) {
    $s = get-service | where {$_.Name -eq $serviceName}
    if($s -and $s.Status -eq "Stopped") { net start $serviceName }
}

CheckStopService nova-compute
CheckStopService neutron-hyperv-agent
CheckStopService ceilometer-agent-compute

if(Is2012OrAbove) {
    stop-vm instance-* -Force -TurnOff -Passthru | Remove-Vm -Force
}
else {
    Import-Module "$ENV:ProgramFiles\modules\HyperV\HyperV.psd1"
    Get-VM instance-* | where {$_.EnabledState -eq 2}  | Stop-VM -Wait -Force
    Get-VM instance-* | Remove-VM -Force -Wait
    Remove-Module HyperV
}

$instancesDir = "C:\OpenStack\Instances"
If  (Test-Path $instancesDir) {
    rmdir $instancesDir -Recurse -Force
}

del C:\OpenStack\Log\*

CheckStartService nova-compute
CheckStartService neutron-hyperv-agent
CheckStartService ceilometer-agent-compute
