$ErrorActionPreference = "Stop"

$products = gwmi Win32_Product -filter "Vendor = 'Cloudbase Solutions Srl'" | where {$_.Caption.StartsWith('OpenStack Hyper-V ')}
if ($products) {
    $msi_log_path="C:\OpenStack\Log\uninstall_log.txt"
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

$pythonProcesses = get-process | where {$_.Path -eq "${ENV:ProgramFiles(x86)}\Cloudbase Solutions\OpenStack\Nova\Python27\python.exe"}
foreach($p in $pythonProcesses) {
    Write-Warning "Killing OpenStack Python process. This process should not be alive!"
    $p | kill -Force
}

$appPath = "${ENV:ProgramFiles(x86)}\Cloudbase Solutions\OpenStack\Nova"

if(Test-Path $appPath) {
    rmdir -Recurse -Force $appPath
}

# Remove common js files used by the installer
# This needs to be added to the installer
del $env:SystemRoot\Temp\*.js -Force
