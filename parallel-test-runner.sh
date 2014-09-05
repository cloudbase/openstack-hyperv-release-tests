#!/bin/bash

# Make sure we kill the entire process tree when exiting
trap 'kill 0' SIGINT SIGTERM

function run_test_retry(){
    local tests_file=$1
    local tmp_log_file=$2
    local i=0
    local exit_code=0

    pushd . > /dev/null
    cd $tests_dir

    while : ; do
        > $tmp_log_file
        testr run --subunit --load-list=$tests_file > $tmp_log_file 2>&1
        subunit-stats $tmp_log_file > /dev/null
        exit_code=$?
        ((i++))
        ( [ $exit_code -eq 0 ] || [ $i -ge $max_attempts ] ) && break
        echo "Test $tests_file failed. Retrying count: $i"
    done

    popd > /dev/null

    echo $exit_code
}

function get_tests_range() {
    local i=$1
    if [ $i -lt ${#tests[@]} ]; then
        local test=${tests[$i]}
        local test_class=${test%.*}
        local j=$i
        if [ $run_isolated -eq 0 ]; then
            for test in ${tests[@]:$((i+1))}; do
                local test_class_match=${test%.*}
                if [ "$test_class" == "$test_class_match" ]; then
                    ((j++))
                else
                    break
                fi
            done
        fi

        echo $i $j
    fi
}

function get_next_test_idx_range() {
   (
        flock -x 200
        local test_idx=$(<$cur_test_idx_file)
        local test_idx_range=( $(get_tests_range $test_idx) )

        if [ ${#test_idx_range[@]} -gt 0 ]; then
            test_idx=${test_idx_range[1]}
            ((test_idx++))
            echo $test_idx > $cur_test_idx_file
            echo ${test_idx_range[@]}
        fi
   ) 200>$lock_file_1
}

function parallel_test_runner() {
    local runner_id=$1
    while : ; do
        local test_idx_range=( $(get_next_test_idx_range) )

        if [ ${#test_idx_range[@]} -eq 0 ]; then
            break
        fi

        local range_start=${test_idx_range[0]}
        local range_end=${test_idx_range[1]}
        local tmp_tests_file=$(tempfile)
        local l=$((range_end-range_start+1))

        for test in ${tests[@]:$range_start:$l}; do
            echo $test >> $tmp_tests_file
        done

        local tmp_log_file="$tmp_log_file_base"_"$range_start"

        echo "Test runner $runner_id is starting tests from $((range_start+1)) to $((range_end+1)) out of ${#tests[@]}:"
        cat $tmp_tests_file
        echo

        local test_exit_code=$(run_test_retry $tmp_tests_file $tmp_log_file)
        rm $tmp_tests_file

        echo "Test runner $runner_id finished tests from $((range_start+1)) to $((range_end+1)) out of ${#tests[@]} with exit code: $test_exit_code"
    done
}


tests_file=$1
tests_dir=$2
log_file=$3
max_parallel_tests=${4:-10}
max_attempts=${5:-5}
run_isolated=${6:-0}

tests=(`awk '{print}' $tests_file`)

cur_test_idx_file=$(tempfile)
echo 0 > $cur_test_idx_file

lock_file_1=$(tempfile)
tmp_log_file_base=$(tempfile)

pids=()
for i in $(seq 1 $max_parallel_tests); do
    parallel_test_runner $i &
    pids+=("$!")
done

for pid in ${pids[@]}; do
    wait $pid
done

rm $cur_test_idx_file

> $log_file
for i in $(seq 0 $((${#tests[@]}-1))); do
    tmp_log_file="$tmp_log_file_base"_"$i"
    if [ -f "$tmp_log_file" ]; then
        cat $tmp_log_file >> $log_file
        rm $tmp_log_file
    fi
done

rm $tmp_log_file_base
rm $lock_file_1

echo "Test execution completed in $SECONDS seconds."

subunit-stats $log_file > /dev/null
exit $?

