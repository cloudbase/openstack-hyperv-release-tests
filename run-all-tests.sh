#!/bin/bash

tests_dir=$1
parallel_tests=${2:-8}
max_attempts=${3:-5}
log_file=${4:-"subunit-output.log"}
results_html_file=${5:-"results.html"}

BASEDIR=$(dirname $0)

tests_file=$(tempfile)
$BASEDIR/get-tests.sh $tests_dir > $tests_file

echo "Running tests from: $tests_file"

$BASEDIR/parallel-test-runner.sh $tests_file $tests_dir $log_file $parallel_tests $max_attempts

log_tmp=$(tempfile)
$BASEDIR/parallel-test-runner.sh isolated-tests.txt $tests_dir $log_tmp $parallel_tests $max_attempts 1

cat $log_tmp >> $log_file
rm $log_tmp
rm $tests_file

echo "Generating HTML report..."
$BASEDIR/get-results-html.sh $log_file $results_html_file

subunit-stats $log_file > /dev/null
exit_code=$?

echo "Total execution time: $SECONDS seconds."
exit $exit_code

