#!/bin/sh
set -e
# Figure out where we are being run
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
MINIO_SERVER_SCRIPT="$SCRIPTPATH/LaunchMinioServer.sh"
#
EVANS_SCSI_PREFIX='scsi-35000c500a'
MACH2_SCSI_PREFIX='scsi-36000c500a'
NYTRO_SCSI_PREFIX='scsi-35000c5003'
MACH2_WWN_PREFIX='wwn-0x6000c500a'
EVANS_WWN_PREFIX='wwn-0x5000c500a'
TATSU_WWN_PREFIX='wwn-0x5000c5009'
NYTRO_WWN_PREFIX='wwn-0x5000c5003'

#DISK_TYPE='ST10000'
DISK_STORE_TYPE='ST16000NM'
DISK_CACHE_TYPE='XS3840'
MAX_STORE_DISK_CNT=32
MAX_CACHE_DISK_CNT=6
MNT_TOP_DIR='/minio_test'
MNT_STORE_PREFIX='disk'
MNT_CACHE_PREFIX='cache'
#PRG_CHAR="•"
PRG_CHAR="·"
PAD_STR='000'
PAD_LEN=$(( $(echo $PAD_STR | wc -c) - 1 ))

CACHE_LIST=""

OSD_READ_AHEAD=4096
OSD_SCHEDULER='none'
#OSD_SCHEDULER='deadline'

declare -a SCHEDULERS 
SCHEDULERS=("none" "mq-deadline" "kyber" "bfq")

declare -a CACHE_DEVS
declare -a STORE_DEVS

for DRV in $(lsblk -npS -o NAME,VENDOR,MODEL,SIZE | grep "${DISK_STORE_TYPE}" | sort | awk '{print $1}' )
do
	STORE_DEVS+=(${DRV})
done
for DRV in $(lsblk -npS -o NAME,VENDOR,MODEL,SIZE | grep "${DISK_CACHE_TYPE}" | sort | awk '{print $1}' )
do
	CACHE_DEVS+=(${DRV})
done

CACHE_DEV_CNT="${#CACHE_DEVS[*]}"
STORE_DEV_CNT="${#STORE_DEVS[*]}"
echo "CacheDevCnt=$CACHE_DEV_CNT"
echo "StoreDevCnt=$STORE_DEV_CNT"

SetDrvQueue() {
	setting=$1
	echo "$HOSTNAME: Setting Disk Scheduler to $setting"
	for disk in "${STORE_DEVS[@]}"
	do
		DRV=$(echo $disk | awk -F '/' '{print $3}')
		echo ${setting} >/sys/block/${DRV}/queue/scheduler
	done
	wait
}
SetDrvQueue $1
