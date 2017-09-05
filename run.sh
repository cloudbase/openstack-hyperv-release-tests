#!/bin/bash
set -e

BASEDIR=$(dirname $0)

. $BASEDIR/utils.sh

function setup_win_host() {
    local win_host=$1
    echo "Setting up host: $win_host"

    # Make sure git is in the PATH on the host, e.g.:
    # setx /m PATH "$ENV:Path;${ENV:ProgramFiles(x86)}\Git\bin"
    cmd="if(!(Test-Path (Join-Path $repo_dir .git))) {
        if(!(Test-Path $repo_dir)) {
            mkdir $repo_dir
        };
        cd (Split-Path $repo_dir -Parent);
        git clone $git_repo_url;
        if(\$LASTEXITCODE) { throw \\\"git clone failed\\\" }
    } else {
        cd $repo_dir;
        
        if(\$LASTEXITCODE) { throw \\\"git pull failed\\\" }
    }"
    run_wsman_ps $win_host "$cmd"
}

function uninstall_compute() {
    local win_host=$1
    echo "Uninstalling OpenStack compute services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\uninstallnova.ps1"
    echo "OpenStack compute services uninstalled on: $win_host"
}

function uninstall_cinder() {
    local win_host=$1
    echo "Uninstalling OpenStack cinder services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\uninstallcinder.ps1"
    echo "OpenStack cinder services uninstalled on: $win_host"
}

function install_compute() {
    local win_host=$1
    local devstack_host=$2
    local password=$3
    local msi_url=$4
    local use_ovs=$5
    echo "Installing OpenStack compute services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\installnova.ps1 -DevstackHost $devstack_host -Password $password -InstallerUrl $msi_url -UseOvs \$$use_ovs"
    echo "OpenStack compute services installed on: $win_host"
}

function install_cinder() {
    local win_host=$1
    local devstack_host=$2
    local password=$3
    local msi_url=$4
    local volume_driver=$5
    echo "Installing OpenStack cinder services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\installcinder.ps1 -DevstackHost $devstack_host -Password $password -Installer $msi_url -VolumeDrivers $volume_driver"
    echo "OpenStack cinder services installed on: $win_host"
}

function restart_compute_services() {
    local win_host=$1
    local neutron_service=$2
    echo "Restarting OpenStack compute services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\restartcomputeservices.ps1 -NeutronAgent $neutron_service"
}

function restart_cinder_services() {
    local win_host=$1
    echo "Restarting OpenStack cinder services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\restartcinderservices.ps1"
}

function stop_compute_services() {
    local win_host=$1
    local neutron_service=$2
    echo "Stopping OpenStack compute services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\stopcomputeservices.ps1 -NeutronAgent $neutron_service"
}

function stop_cinder_services() {
    local win_host=$1
    echo "Stopping OpenStack cinder services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\stopcinderservices.ps1"
}

function get_config_tests() {
    cat $config_file | python -c "import yaml; import sys; config=yaml.load(sys.stdin); print ' '.join(config.keys())"
}

function get_config_cinder_driver() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print config[\"$test_name\"].get('cinder_driver', 'iscsiDriver')"
}

function get_config_cinder_host() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print config[\"$test_name\"].get('cinder_host')"
}

function get_config_test_test_suite() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print config[\"$test_name\"].get('test_suite', 'default')"
}

function get_config_test_include_default() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print config[\"$test_name\"].get('include_default', True)"
}

function get_config_test_devstack() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
test=config[\"$test_name\"]
print ' '.join(['[%(k)s]=%(v)s' % {'k': k, 'v': v}
                for (k,v) in test['devstack'].items()])"
}

function get_config_test_hosts() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print ' '.join(config[\"$test_name\"]['hosts'].keys())"
}

function get_config_test_host_config_files() {
    local test_name=$1
    local host_name=$2
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print ' '.join(config[\"$test_name\"]['hosts'][\"$host_name\"].keys())"
}

function get_config_test_host_config_file_sections() {
    local test_name=$1
    local host_name=$2
    local host_config_file=$3
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print ' '.join(config[\"$test_name\"]['hosts'][\"$host_name\"][\"$host_config_file\"].keys())"
}

function get_config_test_host_config_file_section_entries() {
    local test_name=$1
    local host_name=$2
    local host_config_file=$3
    local section_name=$4
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print ' '.join(['[%(k)s]=%(v)s' % {'k': k, 'v': v} for (k,v) in
               config[\"$test_name\"]['hosts'][\"$host_name\"][\"$host_config_file\"][\"$section_name\"].items()])"
}

function get_config_use_ovs() {
    local test_name=$1
    cat $config_file | python -c "import yaml;
import sys;
config=yaml.load(sys.stdin);
print config[\"$test_name\"].get('use_ovs', False)"
}

function copy_devstack_config_files() {
    local dest_dir=$1

    mkdir -p $dest_dir
    folders=("/etc/ceilometer" "/etc/cinder" "/etc/glance" "/etc/heat" "/etc/keystone" "/etc/nova" "/etc/neutron" "/etc/switf")
    for folder in ${folders[@]}
    do
        # Some of these folders may not exist, if that is the case, log and continue
        scp -i $ssh_key -r "$DEVSTACK_USER@$DEVSTACK_IP_ADDR:$folder" $dest_dir || echo "Could not find $folder on devstack host"
    done

    mkdir $dest_dir/tempest
    scp -i $ssh_key -r "$DEVSTACK_USER@$DEVSTACK_IP_ADDR:/opt/stack/tempest/etc" $dest_dir/tempest || echo "Could not find /opt/stack/tempest/etc on devstack host"
}

function copy_devstack_logs() {
    local container_logs_dir=$1
    local destination_logs=$2

    scp -i $ssh_key -r "$DEVSTACK_USER@$DEVSTACK_IP_ADDR:$container_logs_dir/*" $destination_logs
}

function copy_devstack_screen_logs() {
    local container_screen_logs_dir=$1
    local destination_logs=$2

    scp -i $ssh_key -r "$DEVSTACK_USER@$DEVSTACK_IP_ADDR:$container_screen_logs_dir/*" $destination_logs
}

function copy_tempest_results() {
    local container_tempest_dir=$1
    local destination_logs=$2

    scp -i $ssh_key -r "$DEVSTACK_USER@$DEVSTACK_IP_ADDR:$container_tempest_dir/*" $destination_logs

}

function setup_compute_host() {
    local test_name=$1
    local host_name=$2
    local use_ovs=$3

    echo "Configuring host: $host_name"

    # Make sure the host's time offset is acceptable
    check_host_time $host_name

    exec_with_retry 15 2 setup_win_host $host_name
    exec_with_retry 20 15 uninstall_compute $host_name
    exec_with_retry 20 15 install_compute $host_name $DEVSTACK_IP_ADDR "$DEVSTACK_PASSWORD" $compute_msi_url $use_ovs

    host_config_files=(`get_config_test_host_config_files $test_name $host_name`)
    for host_config_file in ${host_config_files[@]};
    do
        sections=(`get_config_test_host_config_file_sections $test_name $host_name $host_config_file`)
        for section in ${sections[@]};
        do
             declare -A config_entries
             eval "config_entries=(`get_config_test_host_config_file_section_entries $test_name $host_name $host_config_file $section`)"
             for entry_name in ${!config_entries[@]};
             do
                 set_win_config_file_entry $host_name "$host_config_dir\\$host_config_file" $section $entry_name "${config_entries[$entry_name]}"
             done
        done
    done
}

function setup_cinder_host() {
    local test_name=$1
    local host_name=$2

    cinder_driver=`get_config_cinder_driver $test_name`
    echo "Configuring host: $host_name with cinder driver: $cinder_driver"

    # Make sure the host's time offset is acceptable
    check_host_time $host_name

    exec_with_retry 15 2 setup_win_host $host_name
    exec_with_retry 20 15 uninstall_cinder $host_name
    exec_with_retry 20 15 install_cinder $host_name $DEVSTACK_IP_ADDR "$DEVSTACK_PASSWORD" $cinder_installer_url $cinder_driver
}

# parameter initialization.
compute_msi_url=$1
shift

while [[ $# -gt 0 ]]
do
    key=$1
    case $key in
        --cinder_installer_url|--cinder-installer-url)
        cinder_installer_url=$2
        shift # past argument
        ;;
        --branch)
        DEVSTACK_BRANCH=$2
        DEVSTACK_TAG=$2
        shift # past argument
        ;;
        --test_suite|--test-suite)
        test_suite_override=$2
        shift
        ;;
        --*)
            # unknown option
            echo "Usage: $0 <compute_msi_url> [--cinder-installer-url cinder_installer_url] [--branch <devstack_branch>] [--test-suite <test_suite>] [test_name]+"
            exit 1
        ;;
        *)
            # not a keyword argument. break.
            break
        ;;
    esac
    shift
done

test_names_subset=${@}

if [ $DEVSTACK_TAG == "stable/kilo" ]; then
    DEVSTACK_TAG="kilo-eol"
fi

if [ -z "$compute_msi_url" ];
then
    echo "Usage: $0 <compute_msi_url> [--cinder-installer-url cinder_installer_url] [--branch <devstack_branch>] [--test-suite <test_suite>] [test_name]+"
    exit 1
fi

# Check if the URL is valid
wget -q --spider --no-check-certificate $compute_msi_url || (echo "$compute_msi_url is not a valid url"; exit 1)


if [ -n "$cinder_installer_url" ]; then
    wget -q --spider --no-check-certificate $cinder_installer_url || (echo "$cinder_installer_url is not a valid url"; exit 1)
fi

TEST_HOST_IP_ADDR=`get_host_ip_addr`
export TEST_HOST_IP_ADDR

export DEVSTACK_BRANCH
export DEVSTACK_TAG

# we substitute the "/" character in the branch name with "-" character
# so that the container name will look like devstack-stable-* . Using "/"
# would cause container creation to fail.
DEVSTACK_CONTAINER_NAME="devstack-${DEVSTACK_BRANCH/\//-}"
DEVSTACK_VOLUME_GROUP_NAME=$DEVSTACK_CONTAINER_NAME
export DEVSTACK_CONTAINER_NAME

DEVSTACK_PASSWORD=Passw0rd
export DEVSTACK_PASSWORD

export CONTAINER_USER=$USER
export CONTAINER_PASSWORD=Passw0rd

git_repo_url="https://github.com/cloudbase/openstack-hyperv-release-tests"
repo_dir="C:\\Dev\\openstack-hyperv-release-tests"
win_user=Administrator
win_password=Passw0rd
host_config_dir="C:\\OpenStack\\cloudbase\\nova\\etc"
cinder_host_config_dir="C:\\OpenStack\\cloudbase\\cinder\\etc"
host_logs_dir="/OpenStack/Log"
temp_setup_dir="$HOME/temp_stack_setup"
devstack_dir="$HOME/devstack"
images_dir=$devstack_dir
stack_base_dir="/opt/stack"
tempest_dir="$stack_base_dir/tempest"
config_file="config.yaml"
max_parallel_tests=8
max_attempts=0
tcp_ports=(5672 5000 9292 9696 35357)
ssh_key="$HOME/.ssh/container_rsa"

test_reports_base_dir=`realpath $BASEDIR`/reports

#make sure container doesn't already exist
destroy_container $DEVSTACK_CONTAINER_NAME

start_container $DEVSTACK_CONTAINER_NAME

DEVSTACK_IP_ADDR=`get_container_ip_addr $DEVSTACK_CONTAINER_NAME`
export DEVSTACK_IP_ADDR

export OS_USERNAME=admin
export OS_PASSWORD=$DEVSTACK_PASSWORD
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://$DEVSTACK_IP_ADDR:5000/v2.0

#setup container repos
container_test_dir="$HOME/openstack-hyperv-release-tests"

run_ssh $DEVSTACK_IP_ADDR "rm -rf $container_test_dir" $ssh_key
run_ssh $DEVSTACK_IP_ADDR "git clone $git_repo_url $container_test_dir" $ssh_key
run_ssh $DEVSTACK_IP_ADDR "source $container_test_dir/utils.sh ; clone_pull_repo  $devstack_dir 'https://github.com/openstack-dev/devstack.git' $DEVSTACK_BRANCH" $ssh_key
run_ssh $DEVSTACK_IP_ADDR "source $container_test_dir/utils.sh ; pull_all_git_repos $stack_base_dir $DEVSTACK_BRANCH" $ssh_key

# create temporary remote log dir
container_devstack_logs="$HOME/devstack_logs"
run_ssh $DEVSTACK_IP_ADDR "mkdir -p $container_devstack_logs" $ssh_key
container_screen_logs="$HOME/screen_logs"
run_ssh $DEVSTACK_IP_ADDR "mkdir -p $container_screen_logs" $ssh_key


add_user_to_passwordless_sudoers $USER 70_devstack_hyperv

reports_dir_name=`date +"%Y_%m_%d_%H_%M_%S_%N"`

http_base_url="http://$TEST_HOST_IP_ADDR:8001"

has_failed_tests=0

test_names=(`get_config_tests`)
for test_name in ${test_names[@]};
do
    if [ "${test_names_subset[@]}" ];
        then
        skip_test=1
        for tmp_name in ${test_names_subset[@]};
        do
            if [ "$test_name" == "$tmp_name" ]; then
                skip_test=0
                break
            fi
        done
        if [ $skip_test -ne 0 ]; then
            echo "Skipping test: $test_name"
            continue
        fi
    else
        if [ "`get_config_test_include_default $test_name`" != "True" ]; then
            echo "Skipping test: $test_name. Not included by default"
            continue
        fi
    fi

    echo "Current test: $test_name"

    test_reports_dir="$test_reports_base_dir/$reports_dir_name/$test_name"
    echo "Results dir: $test_reports_dir"

    test_logs_dir="$test_reports_dir/logs"
    test_config_dir="$test_reports_dir/config"
    mkdir -p "$test_logs_dir"
    mkdir -p "$test_config_dir"

    unset DEVSTACK_LIVE_MIGRATION
    unset DEVSTACK_SAME_HOST_RESIZE
    unset DEVSTACK_INTERFACE_ATTACH
    unset DEVSTACK_HEAT_IMAGE_FILE
    unset DEVSTACK_IMAGE_FILE
    unset DEVSTACK_IMAGES_DIR
    unset DEVSTACK_ENABLE_DISABLE_CVOL

    declare -A devstack_config
    eval "devstack_config=(`get_config_test_devstack $test_name`)"
    export DEVSTACK_LIVE_MIGRATION=${devstack_config[live_migration]}
    export DEVSTACK_SAME_HOST_RESIZE=${devstack_config[allow_resize_to_same_host]}
    export DEVSTACK_INTERFACE_ATTACH=false
    export DEVSTACK_ENABLE_DISABLE_CVOL="enable_service"

    # if a Cinder URL has been given, disable c-vol in devstack.
    if [ -n "$cinder_installer_url" ]; then
        export DEVSTACK_ENABLE_DISABLE_CVOL="disable_service"
    fi

    echo "getting images"

    image_url="${devstack_config[image_url]}"
    check_get_image $image_url $images_dir
    DEVSTACK_IMAGE_FILE=`check_get_image $image_url $images_dir`

    heat_image_url="${devstack_config[heat_image_url]}"
    check_get_image $heat_image_url $images_dir
    export DEVSTACK_HEAT_IMAGE_FILE=`check_get_image $heat_image_url $images_dir`

    scp -i $ssh_key "$images_dir/$DEVSTACK_IMAGE_FILE" "$CONTAINER_USER@$DEVSTACK_IP_ADDR:$images_dir"
    scp -i $ssh_key "$images_dir/$DEVSTACK_HEAT_IMAGE_FILE" "$CONTAINER_USER@$DEVSTACK_IP_ADDR:$images_dir"

    export DEVSTACK_IMAGES_DIR=$images_dir
    export DEVSTACK_LOGS_DIR="$test_logs_dir/devstack"
    # Disable access to OpenStack services to any remote host
    firewall_manage_ports "" add disable ${tcp_ports[@]}

    mkdir -p $DEVSTACK_LOGS_DIR

    mkdir -p $temp_setup_dir
    cp local.conf $temp_setup_dir
    cp local.sh $temp_setup_dir

    sed -i "s/<%DEVSTACK_LIVE_MIGRATION%>/$DEVSTACK_LIVE_MIGRATION/g" $temp_setup_dir/local.sh
    sed -i "s/<%DEVSTACK_INTERFACE_ATTACH%>/$DEVSTACK_INTERFACE_ATTACH/g" $temp_setup_dir/local.sh
    sed -i "s#<%DEVSTACK_IMAGES_DIR%>#$DEVSTACK_IMAGES_DIR#g" $temp_setup_dir/local.sh
    sed -i "s/<%DEVSTACK_IMAGE_FILE%>/$DEVSTACK_IMAGE_FILE/g" $temp_setup_dir/local.sh

    sed -i "s#<%DEVSTACK_VOLUME_GROUP_NAME%>#$DEVSTACK_VOLUME_GROUP_NAME#g" $temp_setup_dir/local.conf
    sed -i "s/<%DEVSTACK_SAME_HOST_RESIZE%>/$DEVSTACK_SAME_HOST_RESIZE/g" $temp_setup_dir/local.conf
    sed -i "s/<%DEVSTACK_IP_ADDR%>/$DEVSTACK_IP_ADDR/g" $temp_setup_dir/local.conf
    sed -i "s#<%DEVSTACK_IMAGES_DIR%>#$DEVSTACK_IMAGES_DIR#g" $temp_setup_dir/local.conf
    sed -i "s/<%DEVSTACK_IMAGE_FILE%>/$DEVSTACK_IMAGE_FILE/g" $temp_setup_dir/local.conf
    sed -i "s/<%DEVSTACK_HEAT_IMAGE_FILE%>/$DEVSTACK_HEAT_IMAGE_FILE/g" $temp_setup_dir/local.conf
    sed -i "s/<%DEVSTACK_LIVE_MIGRATION%>/$DEVSTACK_LIVE_MIGRATION/g" $temp_setup_dir/local.conf
    sed -i "s/<%DEVSTACK_PASSWORD%>/$DEVSTACK_PASSWORD/g" $temp_setup_dir/local.conf
    sed -i "s#<%DEVSTACK_BRANCH%>#$DEVSTACK_BRANCH#g" $temp_setup_dir/local.conf
    sed -i "s#<%DEVSTACK_TAG%>#$DEVSTACK_TAG#g" $temp_setup_dir/local.conf
    sed -i "s#<%DEVSTACK_LOGS_DIR%>#$container_screen_logs#g" $temp_setup_dir/local.conf
    sed -i "s#<%DEVSTACK_ENABLE_DISABLE_CVOL%>#$DEVSTACK_ENABLE_DISABLE_CVOL#g" $temp_setup_dir/local.conf


    if [ -n "${devstack_config[Q_ML2_TENANT_NETWORK_TYPE]}" ]; then
        sed -i "s/Q_ML2_TENANT_NETWORK_TYPE=.*/Q_ML2_TENANT_NETWORK_TYPE=${devstack_config[Q_ML2_TENANT_NETWORK_TYPE]}/g" $temp_setup_dir/local.conf
    fi

    if [ -n "${devstack_config[OVS_ENABLE_TUNNELING]}" ]; then
        sed -i "s/OVS_ENABLE_TUNNELING=.*/OVS_ENABLE_TUNNELING=${devstack_config[OVS_ENABLE_TUNNELING]}/g" $temp_setup_dir/local.conf
    fi

    if [ -n "${devstack_config[TUNNEL_ENDPOINT_IP]}" ]; then
        sed -i "/OVS_ENABLE_TUNNELING/ a TUNNEL_ENDPOINT_IP=${devstack_config[TUNNEL_ENDPOINT_IP]}" $temp_setup_dir/local.conf
    fi


    # create temporary remote log dir
    container_devstack_logs="$HOME/devstack_logs"
    run_ssh $DEVSTACK_IP_ADDR "mkdir -p $container_devstack_logs" $ssh_key
    container_screen_logs="$HOME/screen_logs"
    run_ssh $DEVSTACK_IP_ADDR "mkdir -p $container_screen_logs" $ssh_key

    scp -i $ssh_key $temp_setup_dir/local.conf "$CONTAINER_USER@$DEVSTACK_IP_ADDR:$devstack_dir/local.conf"
    scp -i $ssh_key $temp_setup_dir/local.sh "$CONTAINER_USER@$DEVSTACK_IP_ADDR:$devstack_dir/local.sh"

    use_ovs=(`get_config_use_ovs $test_name`)
    if [ "$use_ovs" = True ]; then
        # set endpoint ip on eth1 on the devstack_container
        run_ssh $DEVSTACK_IP_ADDR "sudo ifconfig eth1 ${devstack_config[TUNNEL_ENDPOINT_IP]}/24" $ssh_key
    fi

    run_ssh $DEVSTACK_IP_ADDR "sudo DEBIAN_FRONTEND=noninteractive apt-get install mongodb -y > /dev/null ; sudo rm /var/lib/mongodb/mongod.lock ; sudo service mongodb restart > /dev/null" $ssh_key

    pids=()
    run_ssh $DEVSTACK_IP_ADDR "source $container_test_dir/utils.sh ; exec_with_retry 1 0 stack_devstack $container_devstack_logs $devstack_dir" $ssh_key &
    pids+=("$!")

    host_names=(`get_config_test_hosts $test_name`)
    for host_name in ${host_names[@]};
    do
        setup_compute_host $test_name $host_name $use_ovs &
        pids+=("$!")
    done

    if [ -n "$cinder_installer_url" ]; then
        cinder_host_name=`get_config_cinder_host $test_name`
        setup_cinder_host $test_name $cinder_host_name
    fi

    for pid in ${pids[@]};
    do
        wait $pid
    done

    copy_devstack_logs $container_devstack_logs $DEVSTACK_LOGS_DIR

    if [ "$use_ovs" = True ]; then
        neutron_agent_type="Open vSwitch agent"
        neutron_service="neutron-ovs-agent"
    else
        neutron_agent_type="HyperV agent"
        neutron_service="neutron-hyperv-agent"
    fi

    for host_name in ${host_names[@]};
    do
        firewall_manage_ports $host_name add enable ${tcp_ports[@]}

        exec_with_retry 5 10 restart_compute_services $host_name $neutron_service

        echo "Checking if nova-compute is active on: $host_name"
        exec_with_retry 60 2 check_nova_service_up $host_name
        echo "Checking if neutron Hyper-V agent is active on: $host_name"
        exec_with_retry 60 2 check_neutron_agent_up $host_name \"$neutron_agent_type\"
    done

    if [ -n "$cinder_installer_url" ]; then
        firewall_manage_ports $cinder_host_name add enable ${tcp_ports[@]}
        exec_with_retry 5 10 restart_cinder_services $cinder_host_name
        echo "Checking if cinder-volume service is active on: $cinder_host_name"
        exec_with_retry 60 2 check_cinder_service_up $cinder_host_name
    fi

    exec_with_retry 30 2 check_host_services_count ${#host_names[@]} \"$neutron_agent_type\"

    if [[ "$DEVSTACK_BRANCH" == "stable/ocata" ]] || [[ "$DEVSTACK_BRANCH" == "master" ]]; then
        run_ssh $DEVSTACK_IP_ADDR "url=`grep transport_url /etc/nova/nova-dhcpbridge.conf | awk '{print \$3}'` ; nova-manage cell_v2 simple_cell_setup --transport-url \$url >> \"$HOME/devstack_logs/create_cell.log\"" $ssh_key
    fi

    if [ $test_suite_override ]; then
        test_suite=$test_suite_override
    else
        test_suite=`get_config_test_test_suite $test_name`
    fi


    echo "Running tempest with test suite: $test_suite"
    container_tempest_result_dir="/$HOME/tempest_results"
    run_ssh $DEVSTACK_IP_ADDR  "mkdir -p $container_tempest_result_dir" $ssh_key
    run_ssh $DEVSTACK_IP_ADDR "cd $container_test_dir ; source $container_test_dir/utils.sh ; run_tempest $test_suite $container_tempest_result_dir $max_parallel_tests $max_attempts" $ssh_key

    subunit_log_file="$test_reports_dir/subunit-output.log"

    copy_tempest_results $container_tempest_result_dir $test_reports_dir

    subunit-stats --no-passthrough "$subunit_log_file" || true

    copy_devstack_screen_logs $container_screen_logs $DEVSTACK_LOGS_DIR || true
    copy_devstack_config_files $DEVSTACK_LOGS_DIR

    pids=()
    for host_name in ${host_names[@]};
    do
        exec_with_retry 5 10 stop_compute_services $host_name $neutron_service
        exec_with_retry 15 2 get_win_host_config_files $host_name $host_config_dir "$test_config_dir/$host_name"
        exec_with_retry 20 15 uninstall_compute $host_name &
        pids+=("$!")
    done

    if [ -n "$cinder_installer_url" ]; then
        exec_with_retry 5 10 stop_cinder_services $cinder_host_name
        exec_with_retry 15 2 get_win_host_config_files $cinder_host_name $cinder_host_config_dir "$test_config_dir/$cinder_host_name"
        exec_with_retry 20 15 uninstall_cinder $cinder_host_name &
        pids+=("$!")
        # add cinder_host_name to the host_names array for log collection.
        host_names+=($cinder_host_name)
    fi

    for host_name in ${host_names[@]};
    do
        mkdir -p "$test_logs_dir/$host_name"
        exec_with_retry 5 0 get_win_system_info_log $host_name "$test_logs_dir/$host_name/systeminfo.log" &
        pids+=("$!")
        exec_with_retry 5 0 get_win_hotfixes_log $host_name "$test_logs_dir/$host_name/hotfixes.log" &
        pids+=("$!")
    done

    run_ssh $DEVSTACK_IP_ADDR "source $container_test_dir/utils.sh ; exec_with_retry 5 0 unstack_devstack $container_devstack_logs $devstack_dir" $ssh_key &
    pids+=("$!")

    for pid in ${pids[@]};
    do
        wait $pid
    done

    for host_name in ${host_names[@]};
    do
        exec_with_retry 15 2 get_win_host_log_files $host_name $host_logs_dir "$test_logs_dir/$host_name"
    done

    echo "Removing symlinks from logs"
    find "$test_logs_dir/" -type l -delete
    echo "Compressing log files"
    find "$test_logs_dir/" -name "*.log" -exec gzip {} \;

    for host_name in ${host_names[@]};
    do
        firewall_manage_ports $host_name del enable ${tcp_ports[@]}
    done

    firewall_manage_ports "" del disable ${tcp_ports[@]}

    http_test_base_url=$http_base_url/$reports_dir_name/$test_name
    echo
    echo "Test HTML results: $http_test_base_url/results.html"
    echo "All test logs and config files: $http_test_base_url"
done

echo "Destroying lxc container $DEVSTACK_CONTAINER_NAME"
destroy_container $DEVSTACK_CONTAINER_NAME

if [ -z "$cinder_installer_url" ]; then
    # no loopback device was used if a Cinder installer is given.
    echo "Clearing loopback devices used by the container"
    clear_loop_devices $DEVSTACK_CONTAINER_NAME
fi

echo "Clearing container from known hosts"
ssh-keygen -f ~/.ssh/known_hosts -R $DEVSTACK_IP_ADDR

echo "Done!"

exit $has_failed_tests
