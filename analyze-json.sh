#!/bin/bash


# warp analyze --json put-064-524288-mq-deadline.csv.zst | grep -v 'operations loaded'  | jq '.operations[].throughput | .average_bps,.average_ops'
# cat temp.json | jq '.operations[] | .type,.concurrency,.hosts,.clients,.throughput.average_bps,.throughput.average_ops'
# cat temp.json | jq -r '.operations[] | [.type,.concurrency,.hosts,.clients,.throughput.average_bps,.throughput.average_ops] | join(", ")'
for OP in get put delete
do
	for TST in $(ls ${OP}*.zst)
	do
		prefix="$(echo $TST | sed 's/.csv.zst//g' | sed 's/mq-deadline/mq_deadline/g' | sed 's/-/, /g')"
		echo -n "$prefix, $TST, "
		warp analyze --json $TST | grep -v 'operations loaded' \
		| jq -r '.operations[] | [.type,.concurrency,.hosts,.clients,.single_sized_requests.obj_size,.throughput.average_bps,.throughput.average_ops] | join(", ")' | tr -s '\n' ','
		#| grep -i $OP
		echo 
	done
done
