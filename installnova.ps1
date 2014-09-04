$ErrorActionPreference = "Stop"
[Environment]::CurrentDirectory = $pwd

$products = gwmi Win32_Product -filter "Vendor = 'Cloudbase Solutions Srl'" | where {$_.Caption.StartsWith('OpenStack Hyper-V Nova Compute')}
if ($products) {
    Write-Host "Product already installed"
    exit 0
}

$svc = gwmi -Query "Select * From Win32_Service Where Name='MSiSCSI'"
if ($svc.StartMode -ne 'Auto') {
    $svc.ChangeStartMode('Automatic')
}
if (!$svc.Started) {
    $svc.StartService()
}

$msi = "HyperVNovaCompute_Icehouse_2014_1_2.msi"
if(Test-Path $msi) {
    del $msi
}
(New-Object System.Net.WebClient).DownloadFile("https://www.cloudbase.it/downloads/$msi", $msi)

$devstackHost = "10.14.0.26"
$password = "Passw0rd"

$domainInfo = gwmi Win32_NTDomain
if($domainInfo.DomainName) {
    $domainName = $domainInfo.DomainName[1]
}

$features = @(
"HyperVNovaCompute",
"NeutronHyperVAgent",
"CeilometerComputeAgent",
"iSCSISWInitiator",
"FreeRDP"
)

if($domainName) {
    $features += "LiveMigration"
}

$msiLogPath="C:\OpenStack\Log\install_log.txt"
$logDir = split-path $msiLogPath
if(!(Test-Path $logDir)) {
    mkdir $logDir
}

$msiArgs = "/i $msi /qn /l*v $msiLogPath " + `

"ADDLOCAL=" + ($features -join ",") + " " +

"GLANCEHOST=$devstackHost " +
"RPCBACKEND=RabbitMQ " +
"RPCBACKENDHOST=$devstackHost " +
"RPCBACKENDPASSWORD=Passw0rd " +

"INSTANCESPATH=C:\OpenStack\Instances " +
"LOGDIR=C:\OpenStack\Log " +

"RDPCONSOLEURL=http://${devstackHost}:8000 " +

"ADDVSWITCH=0 " +
"VSWITCHNAME=external " +

"USECOWIMAGES=1 " +
"FORCECONFIGDRIVE=1 " +
"CONFIGDRIVEINJECTPASSWORD=1 " +
"DYNAMICMEMORYRATIO=1 " +
"ENABLELOGGING=1 " +
"VERBOSELOGGING=1 " +

"NEUTRONURL=http://${devstackHost}:9696 " +
"NEUTRONADMINTENANTNAME=service " +
"NEUTRONADMINUSERNAME=neutron " +
"NEUTRONADMINPASSWORD=$password " +
"NEUTRONADMINAUTHURL=http://${devstackHost}:35357/v2.0 " +

"CEILOMETERADMINTENANTNAME=service " +
"CEILOMETERADMINUSERNAME=ceilometer " +
"CEILOMETERADMINPASSWORD=$password " +
"CEILOMETERADMINAUTHURL=http://${devstackHost}:35357/v2.0 "

if ($domainName -and $features -ccontains "LiveMigration") {
    $msiArgs += "LIVEMIGRAUTHTYPE=1 " +
        "MAXACTIVEVSMIGR=8 " +
        "MAXACTIVESTORAGEMIGR=8 " +
        "MIGRNETWORKS=10.14.0.0/16 " +
        "NOVACOMPUTESERVICEUSER=${domainName}\Administrator "
}
else {
    $msiArgs += "NOVACOMPUTESERVICEUSER=$(hostname)\Administrator "
}

$msiArgs += "NOVACOMPUTESERVICEPASSWORD=Passw0rd "

Write-Host "Installing ""$msi"""

$p = Start-Process -Wait "msiexec.exe" -ArgumentList $msiArgs -PassThru
if($p.ExitCode) { throw "msiexec failed" }

Write-Host """$msi"" installed successfully"
