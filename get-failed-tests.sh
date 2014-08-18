#!/bin/bash
cat $1 | subunit-2to1 | grep "failure:" | grep -v "process-returncode"  | grep -v setUpClass | awk '{print $2}'


