Param (
      [String]$NeutronAgent = $(throw "-NeutronAgent is required.")
)

Import-Module .\Utils.psm1

if(Is2012OrAbove) {
    Get-VM instance-* | where {$_.State -eq "Running"} | Stop-VM  -Force -TurnOff
    Get-VM instance-* | Remove-VM -Force
}
else {
    Import-Module "$ENV:ProgramFiles\modules\HyperV\HyperV.psd1"
    Get-VM instance-* | where {$_.EnabledState -eq 2}  | Stop-VM -Wait -Force
    Get-VM instance-* | Remove-VM -Force -Wait
    Remove-Module HyperV
}

$instancesDir = "C:\OpenStack\Instances"
If  (Test-Path $instancesDir) {
    rmdir "${instancesDir}\*" -Recurse -Force
}

$log_files = @("nova-compute.log", "neutron-hyperv-agent.log", "neutron-ovs-agent.log", "ceilometer-polling.log")
foreach($log_file in $log_files) {
    $log_path = Join-Path "C:\OpenStack\Log\" $log_file
    if(Test-Path $log_path) {
        del -Force $log_path
    }
}

CheckStartService nova-compute
CheckStartService $NeutronAgent
CheckStartService ceilometer-polling
