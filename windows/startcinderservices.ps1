Import-Module .\Utils.psm1

$log_files = @("cinder-volume-iscsi.log", "cinder-volume-smb.log")
foreach($log_file in $log_files) {
    $log_path = Join-Path "C:\OpenStack\Log\" $log_file
    if(Test-Path $log_path) {
        del -Force $log_path
    }
}

CheckStartService cinder-volume-iscsi
CheckStartService cinder-volume-smb
