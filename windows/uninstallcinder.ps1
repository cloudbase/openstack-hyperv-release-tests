$ErrorActionPreference = "Stop"

Import-Module .\Utils.psm1

UninstallProduct "Cloudbase Solutions Srl" "OpenStack Cinder" "C:\OpenStack\Log\"

foreach ($serviceName in @("cinder-volume-iscsi", "cinder-volume-smb")) {
    CheckStopService $serviceName $true
}

$appPath = "C:\OpenStack\cloudbase\cinder"
KillPythonProcesses $appPath

if(Test-Path $appPath) {
    rmdir -Recurse -Force $appPath
}

# Remove common js files used by the installer
# This needs to be added to the installer
del $env:SystemRoot\Temp\*.js -Force
