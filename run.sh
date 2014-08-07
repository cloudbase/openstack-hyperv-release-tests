time testr run --parallel --subunit | subunit-2to1 > subunit-output.log 2>&1
python subunit2html.py subunit-output.log

