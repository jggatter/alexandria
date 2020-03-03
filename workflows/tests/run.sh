#!/bin/bash
wdl="$1"
inputs="$2"
workflows="/Users/jggatter/Desktop/Alexandria/alexandria_repository/workflows"

CROMWELL_PATH="/Users/jggatter/Desktop/Alexandria/alexandria_repository/workflows/tests/cromwell/cromwell-*.jar"
CROMWELL_CONFIG="/Users/jggatter/Desktop/Alexandria/alexandria_repository/workflows/tests/cromwell/cromwell.conf"
WORKFLOW_OPTIONS="/Users/jggatter/Desktop/Alexandria/alexandria_repository/workflows/tests/cromwell/cromwell_workflow_options.json"

set -euo pipefail

echo Looking for WDL script starting from the workflows folder
if [ ! -d $workflows ]; then echo ERROR: Dummies folder does not exist!; exit; fi
wdl="$( find $workflows -name "${wdl}" )"
if [ -z $wdl ]; then echo ERROR: WDL script does not exist!; exit; fi 

if [ -z $inputs ]; then
	inputs="${wdl%.wdl}.json"
	#inputs="${inputs%_dummy}.json"
fi

set -x
java -Dconfig.file=${CROMWELL_CONFIG} -jar ${CROMWELL_PATH} run $wdl --inputs $inputs --options $WORKFLOW_OPTIONS