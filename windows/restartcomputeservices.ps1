Param (
      [String]$NeutronAgent = $(throw "-NeutronAgent is required.")
)

.\stopcomputeservices.ps1 -NeutronAgent $NeutronAgent
.\startcomputeservices.ps1 -NeutronAgent $NeutronAgent
