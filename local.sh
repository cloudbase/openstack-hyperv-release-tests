#!/bin/bash
set -e

BASEDIR=$(dirname $0)
if [ -f "$BASEDIR/inc/ini-config" ]; then
    . $BASEDIR/inc/ini-config
else
    . $BASEDIR/functions-common
fi

nova flavor-delete 42
nova flavor-create m1.nano 42 128 1 1

nova flavor-delete 84
nova flavor-create m1.micro 84 128 2 1

nova flavor-delete 451
nova flavor-create m1.heat 451 512 5 1

# Add DNS config to the private network
subnet_id=`neutron net-show -c subnets private | awk '{if (NR == 4) { print $4}}'`
neutron subnet-update $subnet_id --dns_nameservers list=true 8.8.8.8 8.8.4.4

TEMPEST_CONFIG=/opt/stack/tempest/etc/tempest.conf

iniset $TEMPEST_CONFIG compute volume_device_name "sdb"
iniset $TEMPEST_CONFIG compute-feature-enabled rdp_console true
iniset $TEMPEST_CONFIG compute-feature-enabled block_migrate_cinder_iscsi <%DEVSTACK_LIVE_MIGRATION%>
iniset $TEMPEST_CONFIG compute-feature-enabled interface_attach <%DEVSTACK_INTERFACE_ATTACH%>

iniset $TEMPEST_CONFIG validation run_validation true

iniset $TEMPEST_CONFIG scenario img_dir <%DEVSTACK_IMAGES_DIR%>
iniset $TEMPEST_CONFIG scenario img_file <%DEVSTACK_IMAGE_FILE%>
iniset $TEMPEST_CONFIG scenario img_disk_format vhd

IMAGE_REF=`iniget $TEMPEST_CONFIG compute image_ref`
iniset $TEMPEST_CONFIG compute image_ref_alt $IMAGE_REF

sudo ip link set br-ex mtu 1450
