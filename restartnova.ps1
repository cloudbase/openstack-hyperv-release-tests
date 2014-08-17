net stop nova-compute
net stop neutron-hyperv-agent
net stop ceilometer-agent-compute

stop-vm instance-* -Force -TurnOff -Passthru | Remove-Vm -Force

$instancesDir = "C:\OpenStack\Instances"
If  (Test-Path $instancesDir) {
    rmdir $instancesDir -Recurse -Force
}

del C:\OpenStack\Log\*

net start nova-compute
net start neutron-hyperv-agent
net start ceilometer-agent-compute
