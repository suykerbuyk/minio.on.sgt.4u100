#!/bin/sh

set -e

if [ "$#" -ne "2" ] ; then
	echo "Error, need two parameters, start/stop and test name"
	exit 1
fi

OPERATION="${1}"
TESTNAME="${2}"

if [[ "${OPERATION}" == "start" ]] ; then
	echo "starting atop ${TESTNAME}"
	atop 10 | grep 'DSK\|NET\|CPU' >/root/${HOSTNAME}-${TESTNAME}-atop.log &
	echo "starting sar ${TESTNAME}"
	sar 10 >/root/${HOSTNAME}-${TESTNAME}-sar.log &
	echo "starting dstat ${TESTNAME}"
	dstat -tdD total,$(lsblk -p -S | grep ST16000 | awk '{print $1}' | tr '\n' ',') 10 >/root/${HOSTNAME}-${TESTNAME}-dstat.log &
elif [[ "${OPERATION}" == "stop" ]]; then
	killall atop
	killall sar
	killall dstat
else
	echo "Bad operation request, ${OPERATION}"
fi

