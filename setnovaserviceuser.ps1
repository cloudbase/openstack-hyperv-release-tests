import-module .\ServiceUserManagement.ps1

$username = "Administrator"
$password = "Passw0rd" | ConvertTo-SecureString -asPlainText -Force
$c = New-Object System.Management.Automation.PSCredential($username, $password)

Set-ServiceLogonCredentials "nova-compute"  -Credentials $c

