net stop nova-compute
net stop neutron-hyperv-agent
net stop ceilometer-agent-compute

stop-vm instance-* -Force -TurnOff -Passthru | Remove-Vm -Force
rmdir C:\OpenStack\Instances -Recurse -Force
del C:\OpenStack\Log\*

net start nova-compute
net start neutron-hyperv-agent
net start ceilometer-agent-compute
