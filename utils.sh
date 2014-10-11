#!/bin/bash
set -e

BASEDIR=$(dirname $0)

function run_wsman_cmd() {
    local host=$1
    local cmd=$2
    $BASEDIR/wsmancmd.py -u $win_user -p $win_password -U https://$1:5986/wsman $cmd
}

function get_win_files() {
    local host=$1
    local remote_dir=$2
    local local_dir=$3
    smbclient "//$host/C\$" -c "lcd $local_dir; cd $remote_dir; prompt; mget *" -U "$win_user%$win_password"
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
    run_wsman_cmd $host "systeminfo"
}

function get_win_time() {
    local host=$1
    # Seconds since EPOCH
    host_time=`run_wsman_ps $host "[Math]::Truncate([double]::Parse((Get-Date (get-date).ToUniversalTime() -UFormat %s)))" 2>&1`
    # Skip the newline
    echo ${host_time::-1}
}

function set_win_config_file_entry() {
    local win_host=$1
    local host_config_file_path=$2
    local config_section=$3
    local entry_name=$4
    local entry_value=$5
    run_wsman_ps $win_host "cd $repo_dir\\windows; Import-Module .\ini.psm1; Set-IniFileValue -Path \\\"$host_config_file_path\\\" -Section $config_section -Key $entry_name -Value $entry_value"
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
        cd `dirname $repo_dir`
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
    neutron agent-list |  awk 'BEGIN { FS = "[ ]*\\|[ ]+" }; {if (NR > 3 && $4 == host_name && $3 == agent_type && $5 == ":-)"){f=1}} END {exit !f}' host_name=$host_name agent_type="$agent_type"
}

function get_neutron_agent_hosts() {
    local agent_type=${1:-"HyperV agent"}
    neutron agent-list |  awk 'BEGIN { FS = "[ ]*\\|[ ]+" }; {if (NR > 3 && $3 == agent_type && $5 == ":-)"){ print $4 }}' agent_type="$agent_type"
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
