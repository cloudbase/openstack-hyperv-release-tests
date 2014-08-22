#!/bin/bash

log_file=$1
results_html_file=$2

f=$(tempfile)
cat $log_file | subunit-2to1 > $f
python subunit2html.py $f $results_html_file
rm $f

