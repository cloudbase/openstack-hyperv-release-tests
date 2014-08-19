$domainName = "tempest.local"
$domainNetbiosName = "TEMPEST"
$safeModePassword = (ConvertTo-SecureString 'P@ssw0rd' -AsPlainText -Force)

Install-WindowsFeature –Name AD-Domain-Services -IncludeManagementTools

Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName $domainName `
    -DomainNetbiosName $domainNetbiosName `
    -SafeModeAdministratorPassword $safeModePassword `
    -InstallDns -NoRebootOnCompletion -Force

shutdown -r -t 0

