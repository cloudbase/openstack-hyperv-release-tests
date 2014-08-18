#!/bin/bash

log_file=$1

f=$(tempfile)
cat $log_file | subunit-2to1 > $f
python subunit2html.py $f
rm $f

