#!/bin/bash
set -e

array_to_regex()
{
    local ar=(${@})
    local regex=""

    for s in "${ar[@]}"
    do
        if [ "$regex" ]; then
            regex+="\\|"
        fi
        regex+="^"$(echo $s | sed -e 's/[]\/$*.^|[]/\\&/g')
    done
    echo $regex
}

tests_dir=$1
test_suite=${2:-"default"}

BASEDIR=$(dirname $0)

include_tests_file=$BASEDIR/include-tests-$test_suite.txt
exclude_tests_file=$BASEDIR/exclude-tests-$test_suite.txt
isolated_tests_file=$BASEDIR/isolated-tests-$test_suite.txt

include_tests=(`awk 'NF && $1!~/^#/' $include_tests_file`)

if [ -f "$exclude_tests_file" ]; then
    exclude_tests=(`awk 'NF && $1!~/^#/' $exclude_tests_file`)
fi

if [ -f "$isolated_tests_file" ]; then
    isolated_tests=(`awk 'NF && $1!~/^#/' $isolated_tests_file`)
fi

exclude_tests=( ${exclude_tests[@]} ${isolated_tests[@]} )

include_regex=$(array_to_regex ${include_tests[@]})
exclude_regex=$(array_to_regex ${exclude_tests[@]})

if [ ! "$exclude_regex" ]; then
    exclude_regex='^$'
fi

cd $tests_dir
testr list-tests | grep $include_regex | grep -v $exclude_regex
