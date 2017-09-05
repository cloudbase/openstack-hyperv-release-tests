#!/bin/bash
set -e

BASEDIR=$(dirname $0)


### Windows specific utils

function run_wsman_cmd() {
    local host=$1
    local cmd=$2
    $BASEDIR/wsmancmd.py -u $win_user -p $win_password -U https://$1:5986/wsman $cmd
}

function get_win_files() {
    local host=$1
    local remote_dir=$2
    local local_dir=$3
    smbclient "//$host/C\$" -c "lcd $local_dir; cd $remote_dir; prompt; mget *" -U "$win_user%$win_password" --max-protocol=SMB3
}

function run_wsman_ps() {
    local host=$1
    local cmd=$2
    run_wsman_cmd $host "powershell -NonInteractive -ExecutionPolicy RemoteSigned -Command $cmd"
}

function reboot_win_host() {
    local host=$1
    run_wsman_cmd $host "shutdown -r -t 0"
}

function get_win_hotfixes() {
    local host=$1
    run_wsman_cmd $host "wmic qfe list"
}

function get_win_system_info() {
    local host=$1
    run_wsman_ps $host "\"wmic os ; wmic computersystem; wmic cpu ; Get-Disk | Format-List ; ipconfig /all\""
}

function get_win_time() {
    local host=$1
    # Seconds since EPOCH
    host_time=`run_wsman_ps $host "[Math]::Truncate([double]::Parse((Get-Date (get-date).ToUniversalTime() -UFormat %s)))" 2>&1`
    # Skip the newline
    echo ${host_time::-1}
}

function get_win_host_config_files() {
    local host_name=$1
    local host_config_dir=$2
    local local_dir=$3
    mkdir -p $local_dir

    local host_config_dir_esc=`run_wsman_ps $host_name "cd $repo_dir\\windows; Import-Module .\ShortPath.psm1; Get-ShortPathName \\\\\"$host_config_dir\\\\\"" 2>&1`
    get_win_files $host_name "${host_config_dir_esc#*:}" $local_dir
}

function set_win_config_file_entry() {
    local win_host=$1
    local host_config_file_path=$2
    local config_section=$3
    local entry_name=$4
    local entry_value=$5
    run_wsman_ps $win_host "cd $repo_dir\\windows; Import-Module .\ini.psm1; Set-IniFileValue -Path \\\"$host_config_file_path\\\" -Section $config_section -Key $entry_name -Value $entry_value"
}

function get_win_hotfixes_log() {
    local win_host=$1
    local log_file=$2
    echo "Getting hotfixes details for host: $win_host"
    get_win_hotfixes $win_host > $log_file
}

function get_win_system_info_log() {
    local win_host=$1
    local log_file=$2
    echo "Getting system info for host: $win_host"
    get_win_system_info $win_host > $log_file
}

function get_win_host_log_files() {
    local host_name=$1
    local host_logs_dir=$2
    local local_dir=$3
    get_win_files $host_name "$host_logs_dir" $local_dir
}


# Linux specific utils

function check_host_time() {
    local host=$1
    host_time=`get_win_time $host`
    local_time=`date +%s`

    local delta=$((local_time - host_time))
    if [ ${delta#-} -gt 300 ];
    then
        echo "Host $host time offset compared to this host is too high: $delta"
        return 1
    fi
}

function run_ssh() {
    local host=$1;
    local command=$2;
    local ssh_key=$3;
    ssh -o StrictHostKeyChecking=no -i $ssh_key "$USER@$host" $command
}

function run_scp() {
    local host=$1
    local source_file=$2
    local destination_file=$3
    local ssh_key=$4
    scp -i $ssh_key $source_file $destination_file
}

function clear_loop_devices() {
    local container_name=$1
    # expected output of losetup --all:
    #/dev/loop1: [fc00]:23465059 (/opt/stack/data/devstack-stable-ocata-lvmdriver-1-backing-file
    sudo losetup --all | grep $container_name | awk -F':' '{print $1}' | xargs sudo losetup --detach
}

function push_dir() {
    pushd . > /dev/null
}

function pop_dir() {
    popd > /dev/null
}

function check_get_image() {
    local image_url=$1
    local images_dir=$2
    local file_name_tmp="$images_dir/${image_url##*/}"
    local file_name="$file_name_tmp"

    if [ "${file_name_tmp##*.}" == "gz" ]; then
        file_name="${file_name_tmp%.*}"
    fi

    if [ ! -f "$file_name" ]; then
        wget -q $image_url -O $file_name_tmp
        if [ "${file_name_tmp##*.}" == "gz" ]; then
            gunzip "$file_name_tmp"
        fi
    fi

    echo "${file_name##*/}"
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
    neutron agent-list -c agent_type -c host -c alive | awk 'BEGIN { FS = "[ ]*\\|[ ]*" }; {if (NR > 3 && $2 == agent_type && $3 == host_name && $4 == ":-)"){f=1}} END {exit !f}' host_name=$host_name agent_type="$agent_type"
}

function get_neutron_agent_hosts() {
    local agent_type=${1:-"HyperV agent"}
    neutron agent-list -c agent_type -c host -c alive | awk 'BEGIN { FS = "[ ]*\\|[ ]*" }; {if (NR > 3 && $2 == agent_type && $4 == ":-)"){ print $3 }}' agent_type="$agent_type"
}

function check_cinder_service_up() {
    local host_name=$1
    local service_name=${2-"cinder-volume"}
    cinder service-list | awk '{if ($6 ~ $(host_name) && $2 == service_name && $10 == "up" && $8 == "enabled") {f=1}} END {exit !f}' host_name=$host_name service_name=$service_name
}

function get_cinder_service_hosts() {
    local service_name=${1-"cinder-volume"}
    cinder service-list | awk '{if ($2 == service_name && $10 == "up" && $8 == "enabled") {print $4}}' service_name=cinder-volume
}

function check_host_services_count() {
    local expected_hosts_count=$1
    local neutron_agent_type=${2:-"HyperV agent"}

    local nova_compute_hosts=`get_nova_service_hosts | wc -l`
    if [ $expected_hosts_count -ne $nova_compute_hosts ]; then
        echo "Current active nova-compute services: $nova_compute_hosts expected: $expected_hosts_count"
        return 1
    fi

    local hyperv_agent_hosts=`get_neutron_agent_hosts "$neutron_agent_type" | wc -l`
    # we error out only if we have less than the expected number of agent hosts. In case we use
    # ovs neutron agent, we will have an extra agent on the controller.
    if [ $expected_hosts_count -gt $hyperv_agent_hosts ]; then
        echo "Current active neutron Hyper-V agents: $hyperv_agent_hosts expected: $expected_hosts_count"
        return 1
    fi

    # we should only use one cinder-volume service at a time for testing.
    local cinder_volume_services=`get_cinder_service_hosts | wc -l`
    if [ $cinder_volume_services -gt 1 ]; then
        echo "Current active cinder-volume services running: $cinder_volume_services"
        return 1
    fi
}

function exec_with_retry () {
    local max_retries=$1
    local interval=${2}
    local cmd=${@:3}

    # cmd might have backslashes that must be escaped. when evaluating it,
    # the backslashes are interpreted, and they shouldn't be.
    cmd=$(echo $cmd | sed -e 's/\\/\\\\/g')

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

function enable_venv() {
    local venvdir=$1

    if [ ! -d "$venvdir" ]; then
        virtualenv $venvdir
    fi
    source "$venvdir/bin/activate"
}

function get_host_ip_addr() {
    python -c "import socket;
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM);
s.connect(('8.8.8.8', 80));
(addr, port) = s.getsockname();
s.close();
print addr"
}

function firewall_manage_ports() {
    local host=$1
    local cmd=$2
    local target=$3
    local tcp_ports=${@:4}
    local iptables_cmd=""
    local source_param=""
    # TODO: Add parameter / autmate interface discovery
    local iface="eth0"

    if [ "$cmd" == "add" ]; then
        iptables_cmd="-I"
    else
        iptables_cmd="-D"
    fi

    if [ "$target" == "enable" ]; then
        iptables_target="ACCEPT"
    else
        iptables_target="REJECT"
    fi

    if [ "$host" ]; then
        source_param="-s $host"
    fi

    for port in ${tcp_ports[@]};
    do
        sudo iptables $iptables_cmd INPUT -i $iface -p tcp --dport $port $source_param -j $iptables_target
    done
}

function check_copy_dir() {
    local src_dir=$1
    local dest_dir=$2

    if [ -d "$src_dir" ]; then
        cp -r "$src_dir" "$dest_dir"
    fi
}

function add_user_to_passwordless_sudoers() {
    local user_name=$1
    local file_name=$2
    local path=/etc/sudoers.d/$2

    if [ ! -f $file_name ]; then
        sudo sh -c "echo $user_name 'ALL=(ALL) NOPASSWD:ALL' > $path && chmod 440 $path"
    fi
}

function stack_devstack() {
    local log_dir=$1
    local devstack_dir=$2
    local ret_val=0
    push_dir
    cd $devstack_dir
    echo "Running unstack.sh"
    ./unstack.sh > /dev/null 2>&1 || true

    rm -rf $stack_base_dir/*.venv

    echo "Running stack.sh"
    ./stack.sh > "$log_dir/devstack_stack.txt" 2> "$log_dir/devstack_stack_err.txt" || ret_val=$?
    echo "stack.sh - exit code: $ret_val"

    pop_dir
    return $ret_val
}

function unstack_devstack() {
    local log_dir=$1
    local devstack_dir=$2
    local ret_val=0
    push_dir
    cd $devstack_dir
    echo "Running unstack.sh"
    ./unstack.sh > "$log_dir/devstack_unstack.txt" 2> "$log_dir/devstack_unstack_err.txt" || ret_val=$?
    echo "unstack.sh - exit code: $ret_val"

    pop_dir
    return $ret_val
}

function run_tempest() {
    local test_suite=$1
    local test_logs_dir=$2
    local max_parallel_tests=$3
    local max_attempts=$4
    local tempest_dir="/opt/stack/tempest"
    subunit_log_file="$test_logs_dir/subunit-output.log"
    html_results_file="$test_logs_dir/results.html"

    $BASEDIR/run-all-tests.sh $tempest_dir $max_parallel_tests $max_attempts \
    $test_suite "$subunit_log_file" "$html_results_file" \
    > $test_logs_dir/out.txt 2> $test_logs_dir/err.txt \
   || has_failed_tests=1
}


# git specific utils

function clone_pull_repo() {
    local repo_dir=$1
    local repo_url=$2
    local repo_branch=${3:-"master"}

    push_dir
    if [ -d "$repo_dir/.git" ]; then
        cd $repo_dir
        git fetch origin $repo_branch
        git checkout $repo_branch
        git reset --hard
        git clean -f -d
        git pull
    else
        cd `dirname $repo_dir`
        git clone $repo_url
        cd $repo_dir
        if [ "$repo_branch" != "master" ]; then
            git checkout -b $repo_branch origin/$repo_branch
        fi
    fi
    pop_dir
}

function pull_all_git_repos() {
    local parent_dir=$1
    local branch_name=$2
    local remote_name=origin

    for d in $parent_dir/*/; do
        if [ -d "$d/.git" ]; then
            pushd .
            echo $d
            cd $d
            if [[ `git branch -r --list $remote_name/$branch_name` ]]; then
                local repo_branch_name=$branch_name
            else
                local repo_branch_name=master
            fi
            git fetch $remote_name
            git checkout $repo_branch_name
            git reset --hard
            git clean -f -d
            find . -name *.pyc -delete
            git pull $remote_name $repo_branch_name
            popd
        fi
    done
}


# Container specific utils

function get_container_ip_addr() {
     local container_name=$1
     sudo lxc-info -n $container_name | grep IP | awk 'BEGIN { FS = ":[ ]*" } ; { print $2 }'
}

function create_container_template() {
     local container_name=$1
     local container_config_file=$2
     local container_user=$3
     local container_password=$4
     local ssh_key=$5

     echo "Creating container $container_name"
     sudo lxc-create -n $container_name -t ubuntu -f $container_config_file -- --packages=bsdmainutils,git,openvswitch-switch,wget,python-dev,python-pip,build-essential --password $container_password --user $container_user
     echo "Setup paswordless sudo for user $container_user"
     local container_rootfs=/var/lib/lxc/$container_name/rootfs
     sudo sh -c "echo $container_user 'ALL=(ALL) NOPASSWD:ALL' > $container_rootfs/etc/sudoers.d/70_hyperv_devstack && chmod 440 $container_rootfs/etc/sudoers.d/70_hyperv_devstack"

     echo "Starting container $container_name"
     sudo lxc-start -n $container_name -d
     sleep 10

     container_ip=`get_container_ip_addr $container_name`
     echo "Container ip: $container_ip"
     echo "Setup container ssh key"
     sshpass -p $container_password ssh-copy-id -o StrictHostKeyChecking=no -i "$ssh_key.pub" $container_user@$container_ip

     echo "Configure container git ssl verify"
     run_ssh $container_ip "git config --global http.sslVerify false; git config --global https.sslVerify false" $ssh_key

     echo "Creating ovs br-eth1"
     run_ssh $container_ip "sudo ovs-vsctl add-br br-eth1 ; sudo ovs-vsctl add-port br-eth1 eth1" $ssh_key

     echo "Installing networking hyper-v for devstack"
     run_ssh $container_ip "sudo pip install networking-hyperv==3.0.0" $ssh_key

     echo "Stopping container"
     sudo lxc-stop -n $container_name

     echo "Creating container template archive"
     sudo tar -zcvf "/$HOME/devstack_lxc_containers/$container_name-template.tar.gz" -C "/var/lib/lxc/$container_name" .

     echo "Destroying container"
     sudo lxc-destroy -n $container_name
}

function start_container() {
#import container from archive. if it does not exist, create template.
     local container_name=$1
     local container_templates_path="/$HOME/devstack_lxc_containers"
     local container_template_name="$container_name-template.tar.gz"
     local template_file="$container_templates_path/$container_template_name"
     local container_config_file_path="$container_templates_path/devstack_lxc.conf"
     local lxc_dir="/var/lib/lxc"

     if [ ! -f $template_file ];
     then
    echo "No container template found for $container_name. Creating one."
        create_container_template $container_name $container_config_file_path $CONTAINER_USER $CONTAINER_PASSWORD $ssh_key
     fi

     sudo mkdir -p "$lxc_dir/$container_name"
     sudo tar -xvf $template_file -C "$lxc_dir/$container_name"
     sudo lxc-start -n $container_name -d
     sleep 10
}

function destroy_container() {
    local container_name=$1

    sudo lxc-stop -n $container_name || true
    sleep 10
    sudo lxc-destroy -n $container_name || true
}
