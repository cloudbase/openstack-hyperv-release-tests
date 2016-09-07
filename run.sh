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
        git pull;
        if(\$LASTEXITCODE) { throw \\\"git pull failed\\\" }
    }"
    run_wsman_ps $win_host "$cmd"
}

function uninstall_compute() {
    local win_host=$1
    echo "Uninstalling OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\uninstallnova.ps1"
    echo "OpenStack services uninstalled on: $win_host"
}

function install_compute() {
    local win_host=$1
    local devstack_host=$2
    local password=$3
    local msi_url=$4
    local use_ovs=$5
    echo "Installing OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\installnova.ps1 -DevstackHost $devstack_host -Password $password -MSIUrl $msi_url -UseOvs \$$use_ovs"
    echo "OpenStack services installed on: $win_host"
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

function restart_compute_services() {
    local win_host=$1
    local neutron_service=$2
    echo "Restarting OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\restartcomputeservices.ps1 -NeutronAgent $neutron_service"
}

function stop_compute_services() {
    local win_host=$1
    local neutron_service=$2
    echo "Stopping OpenStack services on: $win_host"
    run_wsman_ps $win_host "cd $repo_dir\\windows; .\\stopcomputeservices.ps1 -NeutronAgent $neutron_service"
}

function get_win_host_log_files() {
    local host_name=$1
    local local_dir=$2
    get_win_files $host_name "$host_logs_dir" $local_dir
}

function get_win_host_config_files() {
    local host_name=$1
    local local_dir=$2
    mkdir -p $local_dir

    local host_config_dir_esc=`run_wsman_ps $host_name "cd $repo_dir\\windows; Import-Module .\ShortPath.psm1; Get-ShortPathName \\\\\"$host_config_dir\\\\\"" 2>&1`
    get_win_files $host_name "${host_config_dir_esc#*:}" $local_dir
}

function get_config_tests() {
    cat $config_file | python -c "import yaml; import sys; config=yaml.load(sys.stdin); print ' '.join(config.keys())"
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

function stack_devstack() {
    local log_dir=$1
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
    local ret_val=0
    push_dir
    cd $devstack_dir
    echo "Running unstack.sh"
    ./unstack.sh > "$log_dir/devstack_unstack.txt" 2> "$log_dir/devstack_unstack_err.txt" || ret_val=$?
    echo "unstack.sh - exit code: $ret_val"

    pop_dir
    return $ret_val
}

function check_host_services_count() {
    local expected_hosts_count=$1
    local neutron_agent_type=$2

    local nova_compute_hosts=`get_nova_service_hosts | wc -l`
    if [ $expected_hosts_count -ne $nova_compute_hosts ]; then
        echo "Current active nova-compute services:  $nova_compute_hosts expected: ${#host_names[@]}"
        return 1
    fi

    local hyperv_agent_hosts=`get_neutron_agent_hosts "$neutron_agent_type" | wc -l`
    # we error out only if we have less than the expected number of agent hosts. In case we use
    # ovs neutron agent, we will have an extra agent on the controller.
    if [ $expected_hosts_count -gt $hyperv_agent_hosts ]; then
        echo "Current active neutron Hyper-V agents:  $hyperv_agent_hosts expected: ${#host_names[@]}"
        return 1
    fi
}

function copy_devstack_config_files() {
    local dest_dir=$1

    mkdir -p $dest_dir

    check_copy_dir /etc/ceilometer $dest_dir
    check_copy_dir /etc/cinder $dest_dir
    check_copy_dir /etc/glance $dest_dir
    check_copy_dir /etc/heat $dest_dir
    check_copy_dir /etc/keystone $dest_dir
    check_copy_dir /etc/nova $dest_dir
    check_copy_dir /etc/neutron $dest_dir
    check_copy_dir /etc/swift $dest_dir

    mkdir $dest_dir/tempest
    check_copy_dir $tempest_dir/etc $dest_dir/tempest
}

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

function setup_compute_host() {
    local test_name=$1
    local host_name=$2
    local use_ovs=$3

    echo "Configuring host: $host_name"

    # Make sure the host's time offset is acceptable
    check_host_time $host_name

    exec_with_retry 15 2 setup_win_host $host_name
    exec_with_retry 20 15 uninstall_compute $host_name
    exec_with_retry 20 15 install_compute $host_name $DEVSTACK_IP_ADDR "$DEVSTACK_PASSWORD" $msi_url $use_ovs

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

function enable_venv() {
    local venvdir=$1

    if [ ! -d "$venvdir" ]; then
        virtualenv $venvdir
    fi
    source "$venvdir/bin/activate"
}

msi_url=$1
DEVSTACK_BRANCH=${2:-"stable/icehouse"}
test_suite_override=${3}
test_names_subset=${@:4}

if [ -z "$msi_url" ];
then
    echo "Usage: $0 <msi_url> [devstack_branch] [test_suite] [test_name]+"
    exit 1
fi

# Check if the URL is valid
wget -q --spider --no-check-certificate $msi_url || (echo "$msi_url is not a valid url"; exit 1)

export DEVSTACK_BRANCH

DEVSTACK_IP_ADDR=`get_devstack_ip_addr`
export DEVSTACK_IP_ADDR

DEVSTACK_PASSWORD=Passw0rd
export DEVSTACK_PASSWORD

export OS_USERNAME=admin
export OS_PASSWORD=$DEVSTACK_PASSWORD
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://127.0.0.1:5000/v2.0

git_repo_url="https://github.com/cloudbase/openstack-hyperv-release-tests"
repo_dir="C:\\Dev\\openstack-hyperv-release-tests"
win_user=Administrator
win_password=Passw0rd
host_config_dir="C:\\OpenStack\\cloudbase\\nova\\etc"
host_logs_dir="/OpenStack/Log"
devstack_dir="$HOME/devstack"
images_dir=$devstack_dir
stack_base_dir="/opt/stack"
tempest_dir="$stack_base_dir/tempest"
config_file="config.yaml"
max_parallel_tests=8
max_attempts=5
tcp_ports=(5672 5000 9292 9696 35357)

test_reports_base_dir=`realpath $BASEDIR`/reports

clone_pull_repo $devstack_dir "https://github.com/openstack-dev/devstack.git" $DEVSTACK_BRANCH
pull_all_git_repos $stack_base_dir $DEVSTACK_BRANCH

add_user_to_passwordless_sudoers $USER 70_devstack_hyperv

reports_dir_name=`date +"%Y_%m_%d_%H_%M_%S_%N"`

http_base_url="http://$DEVSTACK_IP_ADDR:8001"

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

    declare -A devstack_config
    eval "devstack_config=(`get_config_test_devstack $test_name`)"
    export DEVSTACK_LIVE_MIGRATION=${devstack_config[live_migration]}
    export DEVSTACK_SAME_HOST_RESIZE=${devstack_config[allow_resize_to_same_host]}
    export DEVSTACK_INTERFACE_ATTACH=false

    image_url="${devstack_config[image_url]}"
    check_get_image $image_url "$images_dir"
    export DEVSTACK_IMAGE_FILE=`check_get_image $image_url "$images_dir"`

    heat_image_url="${devstack_config[heat_image_url]}"
    check_get_image $heat_image_url "$images_dir"
    export DEVSTACK_HEAT_IMAGE_FILE=`check_get_image $heat_image_url "$images_dir"`

    export DEVSTACK_IMAGE_FILE=`check_get_image $image_url "$images_dir"`
    export DEVSTACK_IMAGES_DIR=$images_dir
    export DEVSTACK_LOGS_DIR="$test_logs_dir/devstack"

    # Disable access to OpenStack services to any remote host
    firewall_manage_ports "" add disable ${tcp_ports[@]}

    mkdir -p $DEVSTACK_LOGS_DIR

    cp local.conf $devstack_dir
    cp local.sh $devstack_dir
    sed -i "s/<%DEVSTACK_SAME_HOST_RESIZE%>/$DEVSTACK_SAME_HOST_RESIZE/g" $devstack_dir/local.conf
    
    # NOTE(claudiub): some projects might have some changes done locally, meaning that the branch
    # can't be switched easily. This command will hard-reset and clean every git repo in /opt/stack/
    find /opt/stack/ -name *.git -type d -maxdepth 2 -mindepth 2 -execdir sh -c 'git reset --hard; git clean -f -d' {} +

    if [ -n "${devstack_config[Q_ML2_TENANT_NETWORK_TYPE]}" ]; then
        sed -i "s/Q_ML2_TENANT_NETWORK_TYPE=.*/Q_ML2_TENANT_NETWORK_TYPE=${devstack_config[Q_ML2_TENANT_NETWORK_TYPE]}/g" $devstack_dir/local.conf
    fi

    if [ -n "${devstack_config[OVS_ENABLE_TUNNELING]}" ]; then
        sed -i "s/OVS_ENABLE_TUNNELING=.*/OVS_ENABLE_TUNNELING=${devstack_config[OVS_ENABLE_TUNNELING]}/g" $devstack_dir/local.conf
    fi

    if [ -n "${devstack_config[TUNNEL_ENDPOINT_IP]}" ]; then
        sed -i "/OVS_ENABLE_TUNNELING/ a TUNNEL_ENDPOINT_IP=${devstack_config[TUNNEL_ENDPOINT_IP]}" $devstack_dir/local.conf
    fi

    pids=()
    exec_with_retry 5 0 stack_devstack $DEVSTACK_LOGS_DIR &
    pids+=("$!")

    host_names=(`get_config_test_hosts $test_name`)
    use_ovs=(`get_config_use_ovs $test_name`)
    for host_name in ${host_names[@]};
    do
        setup_compute_host $test_name $host_name $use_ovs &
        pids+=("$!")
    done

    for pid in ${pids[@]};
    do
        wait $pid
    done

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

    exec_with_retry 30 2 check_host_services_count ${#host_names[@]} \"$neutron_agent_type\"

    if [ $test_suite_override ]; then
        test_suite=$test_suite_override
    else
        test_suite=`get_config_test_test_suite $test_name`
    fi

    enable_venv "$tempest_dir/.venv"

    echo "Running Tempest tests: $test_suite"
    subunit_log_file="$test_reports_dir/subunit-output.log"
    html_results_file="$test_reports_dir/results.html"
    $BASEDIR/run-all-tests.sh $tempest_dir $max_parallel_tests $max_attempts \
        $test_suite "$subunit_log_file" "$html_results_file" \
        > $test_logs_dir/out.txt 2> $test_logs_dir/err.txt \
        || has_failed_tests=1

    # Exit venv
    deactivate

    subunit-stats --no-passthrough "$subunit_log_file" || true

    copy_devstack_config_files "$test_config_dir/devstack"

    for host_name in ${host_names[@]};
    do
        exec_with_retry 5 10 stop_compute_services $host_name $neutron_service
        firewall_manage_ports $host_name del enable ${tcp_ports[@]}
        exec_with_retry 15 2 get_win_host_config_files $host_name "$test_config_dir/$host_name"
    done

    pids=()
    for host_name in ${host_names[@]};
    do
        exec_with_retry 20 15 uninstall_compute $host_name &
        pids+=("$!")

        mkdir -p "$test_logs_dir/$host_name"
        exec_with_retry 5 0 get_win_system_info_log $host_name "$test_logs_dir/$host_name/systeminfo.log" &
        pids+=("$!")
        exec_with_retry 5 0 get_win_hotfixes_log $host_name "$test_logs_dir/$host_name/hotfixes.log" &
        pids+=("$!")
    done

    exec_with_retry 5 0 unstack_devstack $DEVSTACK_LOGS_DIR &
    pids+=("$!")

    for pid in ${pids[@]};
    do
        wait $pid
    done

    for host_name in ${host_names[@]};
    do
        exec_with_retry 15 2 get_win_host_log_files $host_name "$test_logs_dir/$host_name"
    done

    echo "Removing symlinks from logs"
    find "$test_logs_dir/" -type l -delete
    echo "Compressing log files"
    find "$test_logs_dir/" -name "*.log" -exec gzip {} \;

    firewall_manage_ports "" del disable ${tcp_ports[@]}

    http_test_base_url=$http_base_url/$reports_dir_name/$test_name
    echo
    echo "Test HTML results: $http_test_base_url/results.html"
    echo "All test logs and config files: $http_test_base_url"
done

echo "Done!"

exit $has_failed_tests
