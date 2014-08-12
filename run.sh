#!/bin/bash
set -e
./get-tests.sh > tests.txt
time testr run --parallel --subunit --load-list=tests.txt | subunit-2to1 > subunit-output.log 2>&1
python subunit2html.py subunit-output.log

