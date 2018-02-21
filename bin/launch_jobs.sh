#!/bin/bash

set -o nounset
set -o errexit

TASK_IDS=$(pwd)/$1
INSTANCES=$(pwd)/$2
export SSH_KEY=$4

INSTANCE_COUNT=$(jq '.Reservations[].Instances[].InstanceId' ${INSTANCES} | wc -l)
TASK_COUNT=$(wc -l ${TASK_IDS} | egrep -o '\d+')
TASKS_PER_NODE=$(((${TASK_COUNT} / ${INSTANCE_COUNT})+1))

cd $(mktemp -d -t nucleotides-launch)

split -l ${TASKS_PER_NODE} ${TASK_IDS}

FILES=$(ls)
ADDRESSES=$(jq --raw-output '.Reservations[].Instances[].PublicDnsName' ${INSTANCES})

f() {
	local SRC=$1
	local SERVER=ubuntu@$2
	local DST=tasks.txt
	scp -o "StrictHostKeyChecking no" -i ~/.ssh/${SSH_KEY}.pem ${SRC} ${SERVER}:${DST}
	set -o xtrace
	ssh -o "StrictHostKeyChecking no" -i ~/.ssh/${SSH_KEY}.pem ${SERVER} screen -d -m start_benchmarks.sh ${DST}
}
export -f f

parallel --link --max-procs 1 f ::: ${FILES} ::: ${ADDRESSES}
