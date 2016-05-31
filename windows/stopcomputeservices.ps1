Param (
      [String]$NeutronAgent = $(throw "-NeutronAgent is required.")
)

function CheckStopService($serviceName) {
    $s = get-service | where {$_.Name -eq $serviceName}
    if($s -and $s.Status -ne "Stopped")  {
        Stop-Service $serviceName
    }
}

CheckStopService nova-compute
CheckStopService $NeutronAgent
CheckStopService ceilometer-polling
