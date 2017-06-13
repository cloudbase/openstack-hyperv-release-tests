$ErrorActionPreference = "Stop"

Import-Module .\Utils.psm1

$s = get-service | where {$_.Name -eq "neutron-ovs-agent"}
if ($s) {
    stop-service $s
    sc.exe delete neutron-ovs-agent

    # if ovs was used we will also want to delete the bridges created
    # by the agent to ensure a clean env for the next run.

    ovs-vsctl --if-exists del-br br-tun
    ovs-vsctl --if-exists del-br br-int
}

UninstallProduct "Cloudbase Solutions Srl" "OpenStack Hyper-V" "C:\OpenStack\Log\"

foreach ($serviceName in @("nova-compute", "neutron-hyperv-agent", "ceilometer-polling")) {
    CheckStopService $serviceName $true
}

$appPath = "C:\OpenStack\cloudbase\nova"
KillPythonProcesses $appPath

if(Test-Path $appPath) {
    rmdir -Recurse -Force $appPath
}

# Remove common js files used by the installer
# This needs to be added to the installer
del $env:SystemRoot\Temp\*.js -Force
