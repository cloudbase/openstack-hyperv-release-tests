#!/bin/bash
set -e

BASEDIR=$(dirname $0)

function run_wsman_cmd() {
    local host=$1
    local cmd=$2
    echo $cmd
    $BASEDIR/wsmancmd.py -u Administrator -p Passw0rd -U https://$1:5986/wsman $cmd
}

function run_wsman_ps() {
    local host=$1
    local cmd=$2
    run_wsman_cmd $host "powershell -NonInteractive -ExecutionPolicy RemoteSigned -Command $cmd"
}

function setup_win_host() {
    local win_host=$1

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
    run_wsman_ps $win_host "cd $repo_dir; .\\uninstallnova.ps1"
}

function install_compute() {
    local win_host=$1
    run_wsman_ps $win_host "cd $repo_dir; .\\installnova.ps1"
}

function restart_compute_services() {
    local win_host=$1
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
        if [ "$devstack_branch" != "master" ]; then
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

function stack_devstack() {
    push_dir
    cd $devstack_dir
    ./unstack.sh || true
    ./stack.sh
    pop_dir
}

devstack_branch="stable/icehouse"
repo_dir="C:\\Dev\\devstack-hyperv-incubator"
host_config_dir="\${ENV:ProgramFiles(x86)}\\Cloudbase Solutions\\OpenStack\\Nova\\etc"
devstack_dir="$HOME/devstack"
images_dir=$devstack_dir
config_file="config.yaml"
vhd_image_url="https://raw.githubusercontent.com/cloudbase/ci-overcloud-init-scripts/master/scripts/devstack_vm/cirros.vhd"
vhdx_image_url="https://raw.githubusercontent.com/cloudbase/ci-overcloud-init-scripts/master/scripts/devstack_vm/cirros.vhdx"

clone_pull_repo $devstack_dir "https://github.com/openstack-dev/devstack.git" $devstack_branch
cp local.conf $devstack_dir
cp local.sh $devstack_dir

check_get_image $vhd_image_url "$images_dir/cirros.vhd"
check_get_image $vhdx_image_url "$images_dir/cirros.vhdx"

test_names=(`get_config_tests`)
for test_name in ${test_names[@]};
do
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

    stack_devstack

    host_names=(`get_config_test_hosts $test_name`)
    for host_name in ${host_names[@]};
    do
        setup_win_host $host_name
        uninstall_compute $host_name
        install_compute $host_name

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

        restart_compute_services $host_name
    done

    $BASEDIR/runtests.sh
done

