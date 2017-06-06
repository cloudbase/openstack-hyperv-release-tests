$ErrorActionPreference = "Stop"

Import-Module .\ini.psm1

function Is2012OrAbove() {
    $v = [environment]::OSVersion.Version
    return ($v.Major -gt 6 -or ($v.Major -ge 6 -and $v.Minor -ge 2))
}

function CheckStartService($ServiceName) {
    $s = Get-Service | where {$_.Name -eq $ServiceName}
    if($s -and $s.Status -eq "Stopped") {
        Start-Service $ServiceName
    }
}

function CheckStopService($ServiceName, $RemoveService=$false) {
    $service = Get-Service | where {$_.Name -eq $ServiceName}
    if ($service) {
        if ($service.Status -ne "Stopped")  {
            Stop-Service $ServiceName
        }
        if ($RemoveService) {
            sc.exe delete $ServiceName
        }
    }
}

function UninstallProduct($Vendor, $Caption, $LogPath) {
    try {
        # Nano does not have gwmi.
        $products = gwmi Win32_Product -filter "Vendor = `"$Vendor`"" | Where {$_.Caption.StartsWith($Caption)}
    } catch {}

    if ($products) {
        $msi_log_path = Join-Path $LogPath "uninstall_log.txt"
        $log_dir = split-path $msi_log_path
        if(!(Test-Path $log_dir)) {
            mkdir $log_dir
        }

        foreach($product in $products) {
            Write-Host "Uninstalling ""$($product.Caption)"""
            $p = Start-Process -Wait "msiexec.exe" -ArgumentList "/uninstall $($product.IdentifyingNumber) /qn /l*v $msi_log_path" -PassThru
            if($p.ExitCode) { throw 'Uninstalling "$($product.Caption)" failed'}
            Write-Host """$($product.Caption)"" uninstalled successfully"
        }
    }
}

function KillPythonProcesses($BasePythonPath) {
    foreach ($pythonName in @("Python", "Python27")) {
        $pythonPath = Join-Path $BasePythonPath $pythonName
        $pythonProcesses = Get-Process | Where {$_.Path -eq "$pythonPath\python.exe"}
        foreach($p in $pythonProcesses) {
            Write-Warning "Killing OpenStack Python process. This process should not be alive!"
            $p | kill -Force
        }
    }
}

function ConfigureOsloMessaging($ConfPath, $DevstackHost, $Password)
{
    # oslo_messaging_rabbit
    Set-IniFileValue -Path $ConfPath -Section "oslo_messaging_rabbit" -Key "rabbit_host" -Value "${DevstackHost}"
    Set-IniFileValue -Path $ConfPath -Section "oslo_messaging_rabbit" -Key "rabbit_password" -Value "$Password"
}

function ConfigureNovaCompute($ConfDir, $DevstackHost, $Password, $Version)
{
    $ConfPath = Join-Path $ConfDir "nova.conf"
    cp .\etc\nova.conf $ConfPath
    cp .\etc\policy.json $ConfDir

    # 14.x.x is equivalent with Newton
    if ($Version -lt "14.0.0") {
        Set-IniFileValue -Path $ConfPath -Section "DEFAULT" -Key "compute_driver" -Value "hyperv.nova.driver.HyperVDriver"
    }

    # placement API
    Set-IniFileValue -Path $ConfPath -Section "placement" -Key "password" -Value "$Password"
    Set-IniFileValue -Path $ConfPath -Section "placement" -Key "auth_url" -Value "http://${DevstackHost}:35357/v3"

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

function InstallComputeMSI($MSIPath, $DevstackHost, $Password)
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

    $isInCluster = Get-Service | Where { $_.Name -eq "ClusSvc" }

    # Cluster migration network tags cannot be modified for a node that
    # is inside a cluster
    if($domainName -and !$isInCluster) {
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

    "PLACEMENTPROJECTNAME=service " +
    "PLACEMENTUSERNAME=placement " +
    "PLACEMENTPASSWORD=$Password " +
    "PLACEMENTDOMAINNAME=Default " +
    "PLACEMENTUSERDOMAINNAME=Default " +
    "PLACEMENTREGIONNAME=RegionOne " +
    "PLACEMENTAUTHURL=http://${DevstackHost}:35357/v3 " +

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

function InstallCinderMSI($MSIPath, $DevstackHost, $Password, $Features)
{
    $msiLogPath="C:\OpenStack\Log\install_log.txt"
    $logDir = split-path $msiLogPath
    if(!(Test-Path $logDir)) {
        mkdir $logDir
    }

    $enableIscsi = [int]$Features.Contains('iscsiDriver')
    $enableSmb = [int]$Features.Contains('smbDriver')
    $smbShareList = '{"\\\\127.0.0.1\\cinder_smb_share":{"username":"Administrator","password":"Passw0rd"}}'

    $msiArgs = "/i $MSIPath /qn /l*v $msiLogPath " + `

    "ADDLOCAL=" + ($features -join ",") + " " +

    "INSTALLDIR=C:\OpenStack\cloudbase\cinder " +
    "CINDERCONFFOLDER=C:\OpenStack\cloudbase\cinder\etc " +
    "LOGDIR=C:\OpenStack\Log " +

    "RPCBACKEND=cinder.rpc.impl_kombu " +
    "RPCBACKENDHOST=$DevstackHost " +
    "RPCBACKENDUSER=stackrabbit " +
    "RPCBACKENDPASSWORD=$Password " +

    "GLANCEHOST=http://$DevstackHost " +
    "CINDERSQLCONNECTION=mysql://root:$Password@$DevstackHost/cinder?charset=utf8 " +

    "ISCSIDRIVERENABLED=$enableIscsi " +
    "CHAPENABLED=1 " +

    "SMBDRIVERENABLED=$enableSmb " +
    "SHARELISTJSON=$smbShareList " +

    "ENABLELOGGING=1 " +
    "VERBOSELOGGING=1 "

    Write-Host "Installing ""$MSIPath"""

    $p = Start-Process -Wait "msiexec.exe" -ArgumentList $msiArgs -PassThru
    if($p.ExitCode) { throw "msiexec failed" }

    Write-Host """$MSIPath"" installed successfully"
}

function IsZip($FilePath)
{
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

function InstallComputeZip($ZipPath, $DevstackHost, $Password)
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

    $command = @("$PythonDir\python", "-m", "pip", "freeze")
    # Setting ErrorActionPreference to SilentlyContinue is need on Nano
    # because the warning received by using a smaller version of pip
    # is interpreted as an error
    $ErrorActionPreference = "SilentlyContinue"
    $result = & cmd.exe /c $command[0] $command[1..$command.Length] 2>NULL
    $ErrorActionPreference = "Stop"
    $output = $result | Where-Object { $_ -match '^nova=='}
    # Getting the version from the output. i.e. nova==14.0.0
    $version = $output.Split("=")[2]

    echo "Writing configuration files..."
    mkdir $ConfigDir
    ConfigureNovaCompute $ConfigDir $DevstackHost $Password $version
    ConfigureNeutronHyperVAgent $ConfigDir $DevstackHost $Password
    ConfigureCeilometerPollingAgent $ConfigDir $DevstackHost $Password

    echo "Updating Wrappers..."
    $updateWrapper = Join-Path $PythonScriptsDir 'UpdateWrappers.py'

    $command = @("$PythonDir\python", $updateWrapper, "`"nova-compute = nova.cmd.compute:main`"")
    & $command[0] $command[1..$command.Length]

    $neutronMain = "`"neutron-hyperv-agent = neutron.cmd.eventlet.plugins.hyperv_neutron_agent:main`""
    if ($version -ge "13.0.0") {
        # Versions greater than Mitaka
        $neutronMain = "`"neutron-hyperv-agent = hyperv.neutron.l2_agent:main`""
    }
    $command = @("$PythonDir\python", $updateWrapper, $neutronMain)
    & $command[0] $command[1..$command.Length]

    $command = @("$PythonDir\python", $updateWrapper, "`"ceilometer-polling = ceilometer.cmd.polling:main`"")
    & $command[0] $command[1..$command.Length]

    echo "Registering services..."

    $Binary = "`"$OpenStackService`" nova-compute `"$PythonScriptsDir\nova-compute.exe`" --config-file `"$NovaConf`""
    sc.exe create nova-compute binPath= `"$Binary`" type= own start= auto error= ignore depend= Winmgmt displayname= "OpenStack Nova Compute Service" obj= LocalSystem

    $Binary = "`"$OpenStackService`" neutron-hyperv-agent `"$PythonScriptsDir\neutron-hyperv-agent.exe`" --config-file `"$NeutronConf`""
    sc.exe create neutron-hyperv-agent binPath= `"$Binary`" type= own start= auto error= ignore depend= Winmgmt displayname= "OpenStack Neutron Hyper-V Agent Service" obj= LocalSystem

    $Binary = "`"$OpenStackService`" ceilometer-polling `"$PythonScriptsDir\ceilometer-polling.exe`" --config-file `"$CeilometerConf`""
    sc.exe create ceilometer-polling binPath= `"$Binary`" type= own start= auto error= ignore depend= Winmgmt displayname= "OpenStack Ceilometer Polling Agent Service" obj= LocalSystem

    echo "$zipPath successfully installed!"
}

Export-ModuleMember -function *
