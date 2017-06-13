Param (
      [String]$NeutronAgent = $(throw "-NeutronAgent is required.")
)

Import-Module .\Utils.psm1

CheckStopService nova-compute
CheckStopService $NeutronAgent
CheckStopService ceilometer-polling
