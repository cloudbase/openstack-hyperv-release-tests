Import-Module .\ini.psm1

$nova_conf_path = "$ENV:ProgramFiles (x86)\Cloudbase Solutions\OpenStack\Nova\etc\nova.conf"

Set-IniFileValue -Path $nova_conf_path 'debug' -Value $true
Set-IniFileValue -Path $nova_conf_path 'allow_resize_to_same_host' -Value $false
