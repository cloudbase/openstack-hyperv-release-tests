$ErrorActionPreference = "Stop"

$id = (gwmi win32_product -Filter "Name like 'OpenStack Hyper-V %'").IdentifyingNumber

if($id)
{
    & C:\Dev\MsiZap.Exe TW! "$id"
    if($LASTEXITCODE) { throw "MsiZap failed" }
}
