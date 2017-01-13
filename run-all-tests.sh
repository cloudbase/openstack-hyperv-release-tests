#!/bin/bash

tests_dir=$1
parallel_tests=${2:-8}
max_attempts=${3:-5}
test_suite=${4:-"default"}
log_file=${5:-"subunit-output.log"}
results_html_file=${6:-"results.html"}

BASEDIR=$(dirname $0)

. $BASEDIR/utils.sh

sudo pip install -r "$tests_dir/requirements.txt"

tests_file=$(tempfile)
$BASEDIR/get-tests.sh $tests_dir $test_suite > $tests_file

echo "Running tests from: $tests_file"

if [ ! -d "$tests_dir/.testrepository" ]; then
    push_dir
    cd $tests_dir
    echo "Initializing testr"
    testr init
    pop_dir
fi

touch $log_file

$BASEDIR/parallel-test-runner.sh $tests_file $tests_dir $log_file \
    $parallel_tests $max_attempts || true

isolated_tests_file=$BASEDIR/isolated-tests-$test_suite.txt

if [ -f "$isolated_tests_file" ]; then
    echo "Running isolated tests from: $isolated_tests_file"
    log_tmp=$(tempfile)
    $BASEDIR/parallel-test-runner.sh $isolated_tests_file $tests_dir $log_tmp \
        $parallel_tests $max_attempts 1 || true

    cat $log_tmp >> $log_file
    rm $log_tmp
fi

rm $tests_file

echo "Generating HTML report..."
$BASEDIR/get-results-html.sh $log_file $results_html_file

subunit-stats $log_file > /dev/null
exit_code=$?

echo "Total execution time: $SECONDS seconds."
exit $exit_code

