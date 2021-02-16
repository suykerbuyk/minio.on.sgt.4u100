#!/bin/bash

for OP in get put delete
do
	for TST in $(ls ${OP}*.zst)
	do
		prefix="$(echo $TST | sed 's/.csv.zst//g' | sed 's/mq-deadline/mq_deadline/g' |  sed 's/-/, /g')"
		echo -n "$prefix, $TST, "; warp analyze $TST \
		| grep 'Operation:' -A 1 \
		| tail -1; done	\
		| sed 's/* Average: //g'
	done
