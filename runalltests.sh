#!/bin/bash
set -e

BASEDIR=$(dirname $0)

function run_wsman_cmd() {
    local host=$1
    local cmd=$2
    $BASEDIR/wsmancmd.py -u Administrator -p Passw0rd -U https://$1:5986/wsman $cmd
}

function run_wsman_ps() {
    local host=$1
    local cmd=$2
    run_wsman_cmd $host "powershell -NonInteractive -ExecutionPolicy RemoteSigned -Command $cmd"
}

function setup_win_host() {
    local win_host=$1
    echo "Setting up host: $win_host"

    cmd="if(!(Test-Path (Join-Path $repo_dir .git))) {
        if(!(Test-Path $repo_dir)) {
            mkdir $repo_dir
        };
        cd (Split-Path $repo_dir -Parent);
        git clone https://github.com/cloudbase/devstack-hyperv-incubator
    } else {
        cd $repo_dir;
        git pull
    }"
    run_wsman_ps $win_host "$cmd"
}

function uninstall_compute() {
    local win_host=$1
    echo "Uninstalling OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir; .\\uninstallnova.ps1"
}

function install_compute() {
    local win_host=$1
    echo "Installing OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir; .\\installnova.ps1"
}

function restart_compute_services() {
    local win_host=$1
    echo "Restarting OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir; .\\restartnova.ps1"
}

function set_win_config_file_entry() {
    local win_host=$1
    local host_config_file_path=$2
    local config_section=$3
    local entry_name=$4
    local entry_value=$5
    run_wsman_ps $win_host "cd $repo_dir; Import-Module .\ini.psm1; Set-IniFileValue -Path \\\"$host_config_file_path\\\" -Section $config_section -Key $entry_name -Value $entry_value"

}

function push_dir() {
    pushd . > /dev/null
}

function pop_dir() {
    popd > /dev/null
}

function clone_pull_repo() {
    local repo_dir=$1
    local repo_url=$2
    local repo_branch=${3:-"master"}

    push_dir
    if [ -d "$repo_dir/.git" ]; then
        cd $repo_dir
        git checkout $repo_branch
        git pull
    else
        git clone $repo_url
        cd $repo_dir
        if [ "$repo_branch" != "master" ]; then
            git checkout -b $repo_branch origin/$repo_branch
        fi
    fi
    pop_dir
}

function check_get_image() {
    local image_url=$1
    local file_name=$2
    if [ ! -f "$file_name" ]; then
        wget $image_url -O $file_name
    fi
}

function get_config_tests() {
    cat $config_file | python -c "import yaml; import sys; config=yaml.load(sys.stdin); print ' '.join(config.keys())"
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

function check_nova_service_up() {
    local host_name=$1
    local service_name=${2-"nova-compute"}
    nova service-list | awk '{if ($6 == host_name && $4 == service_name && $12 == "up" && $10 == "enabled") {f=1}} END {exit !f}' host_name=$host_name service_name=$service_name
}

function get_nova_service_hosts() {
    local service_name=${1-"nova-compute"}
    nova service-list | awk '{if ($4 == service_name && $12 == "up" && $10 == "enabled") {print $6}}' service_name=$service_name
}

function check_neutron_agent_up() {
    local host_name=$1
    local agent_type=${2:-"HyperV agent"}
    neutron agent-list |  awk 'BEGIN { FS = "[ ]*\\|[ ]+" }; {if (NR > 3 && $4 == host_name && $3 == agent_type && $5 == ":-)"){f=1}} END {exit !f}' host_name=$host_name agent_type="$agent_type"
}

function get_neutron_agent_hosts() {
    local agent_type=${1:-"HyperV agent"}
    neutron agent-list |  awk 'BEGIN { FS = "[ ]*\\|[ ]+" }; {if (NR > 3 && $3 == agent_type && $5 == ":-)"){ print $4 }}' agent_type="$agent_type"
}

function stack_devstack() {
    push_dir
    cd $devstack_dir
    ./unstack.sh || true
    ./stack.sh
    pop_dir
}

function exec_with_retry () {
    local max_retries=$1
    local interval=${2}
    local cmd=${@:3}

    local counter=0
    while [ $counter -lt $max_retries ]; do
        local exit_code=0
        eval $cmd || exit_code=$?
        if [ $exit_code -eq 0 ]; then
            return 0
        fi
        let counter=counter+1

        if [ -n "$interval" ]; then
            sleep $interval
        fi
    done
    return $exit_code
}

function get_devstack_ip_addr() {
    python -c "import socket;
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM);
s.connect(('8.8.8.8', 80));
(addr, port) = s.getsockname();
s.close();
print addr"
}

function check_host_services_count() {
    local expected_hosts_count=$1

    local nova_compute_hosts=`get_nova_service_hosts | wc -l`
    if [ $expected_hosts_count -ne $nova_compute_hosts ]; then
        echo "Current active nova-compute services:  $nova_compute_hosts expected: ${#host_names[@]}"
        return 1
    fi

    local hyperv_agent_hosts=`get_neutron_agent_hosts | wc -l`
    if [ $expected_hosts_count -ne $hyperv_agent_hosts ]; then
        echo "Current active neutron Hyper-V agents:  $hyperv_agent_hosts expected: ${#host_names[@]}"
        return 1
    fi
}

DEVSTACK_BRANCH="stable/icehouse"
export DEVSTACK_BRANCH

DEVSTACK_IP_ADDR=`get_devstack_ip_addr`
export DEVSTACK_IP_ADDR

repo_dir="C:\\Dev\\devstack-hyperv-incubator"
host_config_dir="\${ENV:ProgramFiles(x86)}\\Cloudbase Solutions\\OpenStack\\Nova\\etc"
devstack_dir="$HOME/devstack"
images_dir=$devstack_dir
config_file="config.yaml"
vhd_image_url="https://raw.githubusercontent.com/cloudbase/ci-overcloud-init-scripts/master/scripts/devstack_vm/cirros.vhd"
vhdx_image_url="https://raw.githubusercontent.com/cloudbase/ci-overcloud-init-scripts/master/scripts/devstack_vm/cirros.vhdx"

clone_pull_repo $devstack_dir "https://github.com/openstack-dev/devstack.git" $DEVSTACK_BRANCH
cp local.conf $devstack_dir
cp local.sh $devstack_dir

check_get_image $vhd_image_url "$images_dir/cirros.vhd"
check_get_image $vhdx_image_url "$images_dir/cirros.vhdx"

test_names=(`get_config_tests`)
for test_name in ${test_names[@]};
do
    echo "Current test: $test_name"

    unset DEVSTACK_LIVE_MIGRATION
    unset DEVSTACK_SAME_HOST_RESIZE
    unset DEVSTACK_IMAGE_FILE
    unset DEVSTACK_IMAGES_DIR

    declare -A devstack_config
    eval "devstack_config=(`get_config_test_devstack $test_name`)"
    export DEVSTACK_LIVE_MIGRATION=${devstack_config[live_migration]}
    export DEVSTACK_SAME_HOST_RESIZE=${devstack_config[allow_resize_to_same_host]}
    export DEVSTACK_IMAGE_FILE="${devstack_config[image]}"
    export DEVSTACK_IMAGES_DIR=$images_dir

    #stack_devstack

    host_names=(`get_config_test_hosts $test_name`)
    for host_name in ${host_names[@]};
    do
        echo "Configuring host: $host_name"

        exec_with_retry 5 10 setup_win_host $host_name
        exec_with_retry 5 10 uninstall_compute $host_name
        exec_with_retry 5 10 install_compute $host_name

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

        exec_with_retry 5 10 restart_compute_services $host_name

        echo "Checking if nova-compute is active on: $host_name"
        exec_with_retry 15 2 check_nova_service_up $host_name
        echo "Checking if neutron Hyper-V agent is active on: $host_name"
        exec_with_retry 15 2 check_neutron_agent_up $host_name
    done

    exec_with_retry 30 2 check_host_services_count ${#host_names[@]}

    #$BASEDIR/runtests.sh

    for host_name in ${host_names[@]};
    do
        exec_with_retry 5 10 uninstall_compute $host_name
    done
done

