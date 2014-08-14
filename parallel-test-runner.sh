#!/bin/bash

# Make sure we kill the entire process tree when exiting
trap "kill 0" SIGINT SIGTERM EXIT

function run_test_retry(){
    local test=$1
    local tmp_log_file=$2
    local i=0
    local exit_code=0

    while : ; do
        > $tmp_log_file
        testr run --subunit $test > $tmp_log_file 2>&1
        subunit-stats $tmp_log_file > /dev/null
        exit_code=$?
        ((i++))
        ( [ $exit_code -eq 0 ] || [ $i -ge $retry_count ] ) && break
        echo "Test $test failed. Retrying count: $i"
    done

    echo $exit_code
}

function get_next_test_idx() {
   (
        flock -x 200
        local test_idx=$(<$cur_test_idx_file)
        echo $test_idx
        ((test_idx++))
        echo $test_idx > $cur_test_idx_file
   ) 200>$lock_file_1
}

function parallel_test_runner() {
    local runner_id=$1
    while : ; do 
        local test_idx=$(get_next_test_idx)
        if [ $test_idx -ge ${#tests[@]} ]; then
            break
        fi
        local test=${tests[$test_idx]}
        local tmp_log_file="$tmp_log_file_base"_"$test_idx"

        echo "Test runner $runner_id is starting test $((test_idx+1)) out of ${#tests[@]}: $test"

        local test_exit_code=$(run_test_retry $test $tmp_log_file)
        
        echo "Test runner $runner_id finished test $((test_idx+1)) out of ${#tests[@]} with exit code: $test_exit_code"
    done
}


tests_file=$1
log_file=$2

max_parallel_tests=5
retry_count=5

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
    cat $tmp_log_file >> $log_file
    rm $tmp_log_file
done

rm $tmp_log_file_base
rm $lock_file_1

subunit-stats $log_file > /dev/null
exit $?

