$ErrorActionPreference = "Stop"

$products = gwmi Win32_Product -filter "Vendor = 'Cloudbase Solutions Srl'" | where {$_.Caption.StartsWith('OpenStack Hyper-V Nova Compute')}

foreach($product in $products) {
    Write-Host 'Uninstalling "$($product.Caption)"'
    $p = Start-Process -Wait "msiexec.exe" -ArgumentList "/uninstall $($product.IdentifyingNumber) /qn /l*v log_uninstall.txt" -PassThru
    if($p.ExitCode) { throw 'Uninstalling "$($product.Caption)" failed'}
}

$appPath = "${ENV:ProgramFiles(x86)}\Cloudbase Solutions\OpenStack\Nova"

if(Test-Path $appPath) {
    rmdir -Recurse -Force $appPath
}
