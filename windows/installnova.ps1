Param(
  [string]$DevstackHost = $(throw "-DevstackHost is required."),
  [string]$Password = $(throw "-Password is required."),
  [string]$InstallerUrl = $(throw "-InstallerUrl is required."),
  [boolean]$UseOvs = $false
 )

 $ErrorActionPreference = "Stop"
[System.IO.Directory]::SetCurrentDirectory($pwd)

Import-Module .\FastWebRequest.psm1
Import-Module .\Utils.psm1

$services = Get-Service | Where { @('nova-compute', 'neutron-hyperv-agent', 'ceilometer-polling') -contains $_.Name }
if ($services.Length -eq 3) {
    Write-Host "Product already installed"
    exit 0
}

$svc = Get-Service MSiSCSI
if ($svc.StartType -ne 'Automatic') {
    Set-Service -InputObject $svc -StartupType Automatic
}
if ($svc.Status -ne 'Running') {
    Start-Service $svc
}

$DownloadFile = "HyperVNovaCompute_Test"
foreach ($FileName in @("$DownloadFile", "$DownloadFile.msi", "$DownloadFile.zip")) {
    if (Test-Path $FileName) {
        del $FileName
    }
}

Invoke-FastWebRequest -Uri $InstallerUrl -OutFile $DownloadFile

if (IsZip "$pwd\$DownloadFile") {
    $ZipPath = "$pwd\$DownloadFile.zip"
    mv $DownloadFile $ZipPath

    InstallComputeZip $ZipPath $DevstackHost $Password
} else {
    $MSIPath = "$pwd\$DownloadFile.msi"
    mv $DownloadFile $MSIPath

    InstallComputeMSI $MSIPath $DevstackHost $Password
}

if ($UseOvs) {
    # we need to stop the neutron hyper-v agent since we will be using ovs
    $s = Get-Service neutron-hyperv-agent
    if ($s) {
        Stop-Service $s
    }
    Write-Host "Setting up ovs-agent service"
    cmd.exe /c .\create_ovs_service.cmd

    $ConfDir = "C:\OpenStack\cloudbase\nova\etc\"
    ConfigureNeutronOVSAgent $ConfDir $DevstackHost $Password

    Write-Host "Ovs-agent set up complete"
}
