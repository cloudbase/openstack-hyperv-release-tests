Param(
  [string]$DevstackHost = $(throw "-DevstackHost is required."),
  [string]$Password = $(throw "-Password is required."),
  [string]$InstallerUrl = $(throw "-InstallerUrl is required."),
  [ValidateSet('iscsiDriver', 'smbDriver')]
  [string[]]$VolumeDrivers = $(throw "-VolumeDrivers is required (comma separated).")
 )

 $ErrorActionPreference = "Stop"
[System.IO.Directory]::SetCurrentDirectory($pwd)

Import-Module .\FastWebRequest.psm1
Import-Module .\Utils.psm1

$services = Get-Service | Where { @('cinder-volume-iscsi', 'cinder-volume-smb') -contains $_.Name }
if ($services.Length -gt 1) {
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

$DownloadFile = "WindowsCinder_Test.msi"
if (Test-Path $DownloadFile) {
    del $DownloadFile
}

Invoke-FastWebRequest -Uri $InstallerUrl -OutFile $DownloadFile
InstallCinderMSI $MSIPath $DevstackHost $Password $VolumeDrivers
