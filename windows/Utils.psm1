$ErrorActionPreference = "Stop"

Import-Module .\ini.psm1

function ConfigureOsloMessaging($ConfPath, $DevstackHost, $Password)
{
    # oslo_messaging_rabbit
    Set-IniFileValue -Path $ConfPath -Section "oslo_messaging_rabbit" -Key "rabbit_host" -Value "${DevstackHost}"
    Set-IniFileValue -Path $ConfPath -Section "oslo_messaging_rabbit" -Key "rabbit_password" -Value "$Password"
}

function ConfigureNovaCompute($ConfDir, $DevstackHost, $Password)
{
    $ConfPath = Join-Path $ConfDir "nova.conf"
    cp .\etc\nova.conf $ConfPath
    cp .\etc\policy.json $ConfDir

    # glance
    Set-IniFileValue -Path $ConfPath -Section "glance" -Key "api_servers" -Value "${DevstackHost}:9292"

    # rdp
    Set-IniFileValue -Path $ConfPath -Section "rdp" -Key "html5_proxy_base_url" -Value "http://${DevstackHost}:8000/"

    # neutron
    Set-IniFileValue -Path $ConfPath -Section "neutron" -Key "url" -Value "http://${DevstackHost}:9696"
    Set-IniFileValue -Path $ConfPath -Section "neutron" -Key "password" -Value "$Password"
    Set-IniFileValue -Path $ConfPath -Section "neutron" -Key "auth_url" -Value "http://${DevstackHost}:35357/v3"

    ConfigureOsloMessaging $ConfPath $DevstackHost $Password
}

function ConfigureNeutronHyperVAgent($ConfDir, $DevstackHost, $Password)
{
    $ConfPath = Join-Path $ConfDir "neutron_hyperv_agent.conf"
    cp .\etc\neutron_hyperv_agent.conf $ConfPath

    $WorkerCount = 1
    # 6.3 is the equivalent of Windows / Hyper-V Server 2012 R2.
    if ([Environment]::OSVersion.Version -ge (New-Object 'Version' 6, 3)) {
        # the installer sets the worker_count as min(12, number_of_processors).
        # copy its behaviour.
        $WorkerCount = [math]::min(12, [System.Environment]::ProcessorCount)
    }

    # AGENT
    Set-IniFileValue -Path $ConfPath -Section "AGENT" -Key "worker_count" -Value "$WorkerCount"

    ConfigureOsloMessaging $ConfPath $DevstackHost $Password
}

function ConfigureNeutronOVSAgent($ConfDir, $DevstackHost, $Password)
{
    $ConfPath = Join-Path $ConfDir "neutron_ovs_agent.conf"
    cp .\etc\neutron_ovs_agent.conf $ConfPath

    # DEFAULT
    Set-IniFileValue -Path $ConfPath -Key "rabbit_host" -Value $DevstackHost
    Set-IniFileValue -Path $ConfPath -Key "rabbit_password" -Value $Password
}

function ConfigureCeilometerPollingAgent($ConfDir, $DevstackHost, $Password)
{
    $ConfPath = Join-Path $ConfDir "ceilometer.conf"
    cp .\etc\ceilometer.conf $ConfPath
    cp .\etc\pipeline.yaml $ConfDir

    # service_credentials
    Set-IniFileValue -Path $ConfPath -Section "service_credentials" -Key "os_auth_url" -Value "http://${DevstackHost}:35357/v3"

    ConfigureOsloMessaging $ConfPath $DevstackHost $Password
}

function InstallMSI($MSIPath, $DevstackHost, $Password)
{
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

    $msiArgs = "/i $MSIPath /qn /l*v $msiLogPath " + `

    "ADDLOCAL=" + ($features -join ",") + " " +

    "INSTALLDIR=C:\OpenStack\cloudbase\nova " +
    "GLANCEHOST=http://$DevstackHost " +
    "RPCBACKEND=RabbitMQ " +
    "RPCBACKENDHOST=$DevstackHost " +
    "RPCBACKENDUSER=stackrabbit " +
    "RPCBACKENDPASSWORD=$Password " +

    "INSTANCESPATH=C:\OpenStack\Instances " +
    "LOGDIR=C:\OpenStack\Log " +

    "RDPCONSOLEURL=http://${DevstackHost}:8000 " +

    "ADDVSWITCH=0 " +
    "VSWITCHNAME=external " +

    "USECOWIMAGES=1 " +
    "FORCECONFIGDRIVE=1 " +
    "CONFIGDRIVEINJECTPASSWORD=1 " +
    "DYNAMICMEMORYRATIO=1 " +
    "ENABLELOGGING=1 " +
    "VERBOSELOGGING=1 " +

    "NEUTRONURL=http://${DevstackHost}:9696 " +
    "NEUTRONADMINTENANTNAME=service " +
    "NEUTRONADMINUSERNAME=neutron " +
    "NEUTRONADMINPASSWORD=$Password " +
    "NEUTRONADMINAUTHURL=http://${DevstackHost}:35357/v3 " +

    "CEILOMETERADMINTENANTNAME=service " +
    "CEILOMETERADMINUSERNAME=ceilometer " +
    "CEILOMETERADMINPASSWORD=$Password " +
    "CEILOMETERADMINAUTHURL=http://${DevstackHost}:35357/v3 "

    if ($domainName -and $features -ccontains "LiveMigration") {
        $msiArgs += "LIVEMIGRAUTHTYPE=1 " +
            "MAXACTIVEVSMIGR=8 " +
            "MAXACTIVESTORAGEMIGR=8 " +
            "MIGRNETWORKSANY=1 " +
            "NOVACOMPUTESERVICEUSER=${domainName}\Administrator "
    }
    else {
        $msiArgs += "NOVACOMPUTESERVICEUSER=$(hostname)\Administrator "
    }

    $msiArgs += "NOVACOMPUTESERVICEPASSWORD=Passw0rd "

    Write-Host "Installing ""$MSIPath"""

    $p = Start-Process -Wait "msiexec.exe" -ArgumentList $msiArgs -PassThru
    if($p.ExitCode) { throw "msiexec failed" }

    Write-Host """$MSIPath"" installed successfully"
}

function IsZip($FilePath) {
    $isZip = $false
    try {
        $stream = New-Object System.IO.StreamReader -ArgumentList @($FilePath)
        $reader = New-Object System.IO.BinaryReader -ArgumentList @($stream.BaseStream)
        $bytes = $reader.ReadBytes(4)
        if ($bytes.Length -eq 4) {
            if ($bytes[0] -eq 80 -and
                $bytes[1] -eq 75 -and
                $bytes[2] -eq 3 -and
                $bytes[3] -eq 4) {
                $isZip = $true
            }
        }
    }
    finally {
        if ($reader) {
            $reader.Dispose()
        }
        if ($stream) {
            $stream.Dispose()
        }
    }

    return $isZip
}

function Unzip($ZipPath, $Destination)
{
    # function will return $false if an error occurs, $true otherwise
    if(Test-Path $Destination) {
        rmdir -Recurse -Force $Destination
    }

    mkdir $Destination
    try {
        # Try without loading System.IO.Compression.FileSystem. This will work by default on Nano
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
    } catch [System.Management.Automation.RuntimeException] {
        # Load System.IO.Compression.FileSystem. This will work on the full version of Windows Server
        Add-Type -assembly "System.IO.Compression.FileSystem"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $Destination)
    }
}

function InstallZip($ZipPath, $DevstackHost, $Password)
{
    $OpenStackDir = 'C:\OpenStack\'
    $OpenStackLogDir = Join-Path $OpenStackDir 'Log'
    $OpenStackInstallDir = Join-Path $OpenStackDir 'cloudbase\nova'

    $ConfigDir = Join-Path $OpenStackInstallDir 'etc'
    $NovaConf = Join-Path $ConfigDir 'nova.conf'
    $NeutronConf = Join-Path $ConfigDir 'neutron_hyperv_agent.conf'
    $CeilometerConf = Join-Path $ConfigDir 'ceilometer.conf'

    $OpenStackService = Join-Path $OpenStackInstallDir "bin\OpenStackService.exe"
    $PythonDir = Join-Path $OpenStackInstallDir "Python"
    $PythonScriptsDir = Join-Path $PythonDir "Scripts"

    echo "Unzipping $ZipPath..."
    Unzip $ZipPath $OpenStackInstallDir

    echo "Writing configuration files..."
    mkdir $ConfigDir
    ConfigureNovaCompute $ConfigDir $DevstackHost $Password
    ConfigureNeutronHyperVAgent $ConfigDir $DevstackHost $Password
    ConfigureCeilometerPollingAgent $ConfigDir $DevstackHost $Password

    echo "Registering services..."

    $Binary = "`"$OpenStackService`" nova-compute `"$PythonDir\python`" `"$PythonScriptsDir\nova-compute-script.py`" --config-file `"$NovaConf`""
    sc.exe create nova-compute binPath= `"$Binary`" type= own start= auto error= ignore depend= Winmgmt displayname= "OpenStack Nova Compute Service" obj= LocalSystem

    $Binary = "`"$OpenStackService`" neutron-hyperv-agent `"$PythonDir\python`" `"$PythonScriptsDir\neutron-hyperv-agent-script.py`" --config-file `"$NeutronConf`""
    sc.exe create neutron-hyperv-agent binPath= `"$Binary`" type= own start= auto error= ignore depend= Winmgmt displayname= "OpenStack Neutron Hyper-V Agent Service" obj= LocalSystem

    $Binary = "`"$OpenStackService`" ceilometer-polling `"$PythonDir\python`" `"$PythonScriptsDir\ceilometer-polling-script.py`" --config-file `"$CeilometerConf`""
    sc.exe create ceilometer-polling binPath= `"$Binary`" type= own start= auto error= ignore depend= Winmgmt displayname= "OpenStack Ceilometer Polling Agent Service" obj= LocalSystem

    echo "$zipPath successfully installed!"
}

Export-ModuleMember -function *
