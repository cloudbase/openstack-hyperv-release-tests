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

include_tests=(`awk 'NF && $1!~/^#/' include-tests.txt`)
exclude_tests=(`awk 'NF && $1!~/^#/' exclude-tests.txt`)
isolated_tests=(`awk 'NF && $1!~/^#/' isolated-tests.txt`)

exclude_tests=( ${exclude_tests[@]} ${isolated_tests[@]} )

include_regex=$(array_to_regex ${include_tests[@]})
exclude_regex=$(array_to_regex ${exclude_tests[@]})

cd /opt/stack/tempest
testr list-tests | grep $include_regex | grep -v $exclude_regex 

