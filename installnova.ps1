$ErrorActionPreference = "Stop"

$svc = gwmi -Query "Select * From Win32_Service Where Name='MSiSCSI'"
if ($svc.StartMode -ne 'Auto') {
    $svc.ChangeStartMode('Automatic')
}
if (!$svc.Started) {
    $svc.StartService()
}

$msi = "HyperVNovaCompute_Icehouse_2014_1_2.msi"

Import-Module BitsTransfer
Start-BitsTransfer "https://www.cloudbase.it/downloads/$msi"

$devstackHost = "10.14.0.26"
$password = "Passw0rd"

$features = @(
"HyperVNovaCompute",
"NeutronHyperVAgent",
"CeilometerComputeAgent",
"iSCSISWInitiator",
"FreeRDP",
"LiveMigration"
)

$msiArgs = "/i $msi /qn /l*v log.txt " + `

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

if ($features -ccontains "LiveMigration") {
    $msiArgs += "LIVEMIGRAUTHTYPE=1 " +
        "MAXACTIVEVSMIGR=8 " +
        "MAXACTIVESTORAGEMIGR=8 " +
        "MIGRNETWORKS=10.14.0.0/16 " +
        "NOVACOMPUTESERVICEUSER=TEMPEST\Administrator "
}
else {
    $msiArgs += "NOVACOMPUTESERVICEUSER=Administrator "
}

$msiArgs += "NOVACOMPUTESERVICEPASSWORD=Passw0rd "

$p = Start-Process -Wait "msiexec.exe" -ArgumentList $msiArgs -PassThru
if($p.ExitCode) { throw "msiexec failed" }
