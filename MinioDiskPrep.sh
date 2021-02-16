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
XFS_CACHE_PREFIX="XFS_CACHE"
XFS_CACHE_PART_SIZE=1048576
#PRG_CHAR="•"
PRG_CHAR="·"
PAD_STR='000'
PAD_LEN=$(( $(echo $PAD_STR | wc -c) - 1 ))

CACHE_LIST=""

declare -a CACHE_DEVS
declare -a XFS_CACHE_DEVS
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

DirCleanUp() {
	# Nothing to do if we don't have the topdir.
	if [ -d "$MNT_TOP_DIR" ] 
	then
		printf "Cleaning up mount point(s)\n "
		for mnt in $(mount -l  | grep "$MNT_TOP_DIR" | awk '{print $3}')
	       	do
			printf "$PRG_CHAR"
			umount "$mnt"
			rmdir "$mnt"
		done
		rm -rf  "$MNT_TOP_DIR"
		printf "\ndone.\n\n"
	fi
}
DirSetUp() {
	if [ ! -d "$MNT_TOP_DIR" ]
	then
		printf "Creating top level disk mount directory\n"
		mkdir "$MNT_TOP_DIR"
		printf "done.\n\n"
	fi

}
StorageDiskPrep() {
	echo "Clearing Storage Devices"
	for disk in "${STORE_DEVS[@]}"
	do
		(dd if=/dev/zero of=$disk bs=1M count=256 2>/dev/null && printf "$PRG_CHAR" ) &
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
	echo  "Formatting storage disks:"
	for disk in "${STORE_DEVS[@]}"
	do
		(mkfs.xfs -q $disk && printf "$PRG_CHAR") &
	done
	printf "\ndone\n\n"
	wait $(jobs -p)
}
MinioCacheDiskPrep() {
	echo "Clearing Cache Devices"
	for disk in "${CACHE_DEVS[@]}"
	do
		(dd if=/dev/zero of=$disk bs=1M count=256 2>/dev/null && printf "$PRG_CHAR" ) &
	done
	wait $(jobs -p)
	printf "\ndone\n\n"

	echo "Formatting cache disks:"
	for disk in "${CACHE_DEVS[@]}"
	do
		mkfs.xfs -q $disk && printf "$PRG_CHAR" &
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
}
XfsCacheDiskPrep() {
	echo "Setting up XFS Cache Devices"
	DSK_NUM=0
	for CACHE_DEV in "${CACHE_DEVS[@]}"
	do
		DEV_STR=$(printf "%02d" "$DSK_NUM")
		echo "Working on cache device $DEV_STR"
		sgdisk --zap-all $CACHE_DEV >/dev/null && \
		sgdisk  -n1::+${XFS_CACHE_PART_SIZE}   -t1:bf00  -c1:${XFS_CACHE_PREFIX}_${DEV_STR}_00\
			-n2::+${XFS_CACHE_PART_SIZE}   -t2:bf00  -c2:${XFS_CACHE_PREFIX}_${DEV_STR}_01\
			-n3::+${XFS_CACHE_PART_SIZE}   -t3:bf00  -c3:${XFS_CACHE_PREFIX}_${DEV_STR}_02\
			-n4::+${XFS_CACHE_PART_SIZE}   -t4:bf00  -c4:${XFS_CACHE_PREFIX}_${DEV_STR}_03\
			-n5::+${XFS_CACHE_PART_SIZE}   -t5:bf00  -c5:${XFS_CACHE_PREFIX}_${DEV_STR}_04\
			-n6::+${XFS_CACHE_PART_SIZE}   -t6:bf00  -c6:${XFS_CACHE_PREFIX}_${DEV_STR}_05\
			-n7::+${XFS_CACHE_PART_SIZE}   -t7:bf00  -c7:${XFS_CACHE_PREFIX}_${DEV_STR}_06\
			-n8::+${XFS_CACHE_PART_SIZE}   -t8:bf00  -c8:${XFS_CACHE_PREFIX}_${DEV_STR}_07\
			-n9::+${XFS_CACHE_PART_SIZE}   -t9:bf00  -c9:${XFS_CACHE_PREFIX}_${DEV_STR}_08\
			-n10::+${XFS_CACHE_PART_SIZE}  -t10:bf00 -c10:${XFS_CACHE_PREFIX}_${DEV_STR}_09\
			-n11::+${XFS_CACHE_PART_SIZE}  -t11:bf00 -c11:${XFS_CACHE_PREFIX}_${DEV_STR}_10\
			-n12::+${XFS_CACHE_PART_SIZE}  -t12:bf00 -c12:${XFS_CACHE_PREFIX}_${DEV_STR}_11\
			${CACHE_DEV} >/dev/null && printf "$PRG_CHAR" &
		DSK_NUM=$((DSK_NUM +1))
	done
	wait $(jobs -p)
	partprobe
	sleep 1
	echo .

	for PART in $(ls /dev/disk/by-partlabel | grep "${XFS_CACHE_PREFIX}" | sort )
	do
		XFS_CACHE_DEVS+=("/dev/disk/by-partlabel/${PART}")
		echo "/dev/disk/by-partlabel/${PART}"
	done
#	for CACHE_DEV in "${XFS_CACHE_DEVS[@]}"
#	do
#		echo $CACHE_DEV
#	done
	printf "done\n"
}
XfsWithCacheStorageDiskPrep() {
	echo "Zapping Storage Devices"
	for disk in "${STORE_DEVS[@]}"
	do
		sgdisk --zap-all $disk >/dev/null &
	done
	wait $(jobs -p)
	echo "Zeroing Storage Devices"
	for disk in "${STORE_DEVS[@]}"
	do
		sgdisk --zap-all $disk >/dev/null && \
		dd if=/dev/zero of=$disk bs=1M count=256 2>/dev/null && printf "$PRG_CHAR" &
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
	echo  "Formatting storage disks:"
	IDX=0
	for disk in "${STORE_DEVS[@]}"
	do

		echo mkfs.xfs -q -f -l logdev=${XFS_CACHE_DEVS[$IDX]} $disk
		mkfs.xfs -q -f -l logdev=${XFS_CACHE_DEVS[$IDX]} $disk &
		#(mkfs.xfs -q -f -l logdev=${XFS_CACHE_DEVS[$IDX]} $disk && printf "$PRG_CHAR") &
		IDX=$((IDX +1))
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
}
MountStorageFileSystems() {
	printf "Mounting Storage File Systems...\n "
	[ -d "$MNT_TOP_DIR" ] || DirSetUp
	DSK_CNT=${STORE_DEV_CNT}
	if [[ ${DSK_CNT} -gt ${MAX_STORE_DISK_CNT} ]] ; then
		DSK_CNT=${MAX_STORE_DISK_CNT}
	fi
	for disk in "${STORE_DEVS[@]}"
	do
		for x in $(seq 1 $DSK_CNT)
		do
			NUM=$(printf "$PAD_STR$x" | tail -c $PAD_LEN)
			MNT_PATH="$MNT_TOP_DIR/${MNT_STORE_PREFIX}${NUM}"
			if [ ! -d "$MNT_PATH" ] 
			then
				mkdir "$MNT_PATH" 
				(mount "$disk" "$MNT_PATH" && printf "$PRG_CHAR") &
				break
			fi
		done
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
}
MountCachedXFSStorageFileSystems() {
	printf "Mounting Storage File Systems...\n "
	[ -d "$MNT_TOP_DIR" ] || DirSetUp
	DSK_CNT=${STORE_DEV_CNT}
	if [[ ${DSK_CNT} -gt ${MAX_STORE_DISK_CNT} ]] ; then
		DSK_CNT=${MAX_STORE_DISK_CNT}
	fi
	for disk in "${STORE_DEVS[@]}"
	do
		for x in $(seq 1 $DSK_CNT)
		do
			NUM=$(printf "$PAD_STR$x" | tail -c $PAD_LEN)
			MNT_PATH="$MNT_TOP_DIR/${MNT_STORE_PREFIX}${NUM}"
			if [ ! -d "$MNT_PATH" ] 
			then
				mkdir "$MNT_PATH" 
				# echo mount "$disk" -o logdev=${XFS_CACHE_DEVS[$((x-1))]}  "$MNT_PATH" && printf "$PRG_CHAR"
				mount "$disk" -o logdev=${XFS_CACHE_DEVS[$((x-1))]}  "$MNT_PATH" && printf "$PRG_CHAR" &
				break
			fi
		done
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
}

MountMinioCacheFileSystems() {
	CACHE_LIST=""
	printf "Mounting Cache File Systems...\n "
	[ -d "$MNT_TOP_DIR" ] || DirSetUp
	DSK_CNT=${STORE_DEV_CNT}
	if [[ ${DSK_CNT} -gt ${MAX_CACHE_DISK_CNT} ]] ; then
		DSK_CNT=${MAX_CACHE_DISK_CNT}
	fi
	for disk in "${CACHE_DEVS[@]}"
	do
		for x in $(seq 1 $DSK_CNT)
		do
			NUM=$(printf "$PAD_STR$x" | tail -c $PAD_LEN)
			MNT_PATH="$MNT_TOP_DIR/${MNT_CACHE_PREFIX}${NUM}"
			if [ ! -d "$MNT_PATH" ] 
			then
				mkdir "$MNT_PATH" 
				(mount "$disk" "$MNT_PATH" && printf "$PRG_CHAR") &
				CACHE_LIST="${CACHE_LIST},${MNT_PATH}"
				break
			fi
		done
	done
	wait $(jobs -p)
	printf "\ndone\n\n"
}
#minio server http://minio-{1...4}:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} 2>&1 >>/var/log/minio.log
CreateMinioLauncher() {
	printf "Creating minio server launch script\n"
	disk_1="$(ls $MNT_TOP_DIR/ | sort | head -1 | awk -F "/" '{print $NF}')"
	disk_1="$(printf $disk_1 | tail -c $PAD_LEN)"
	disk_n="$(ls $MNT_TOP_DIR/ | sort | tail -1 | awk -F "/" '{print $NF}')"
	disk_n="$(printf $disk_n | tail -c $PAD_LEN)"
	cat <<-SCRIPT >$MINIO_SERVER_SCRIPT
		ulimit -n 1000000
		export MINIO_ACCESS_KEY=\${MINIO_ACCESS_KEY:=admin}
		export MINIO_SECRET_KEY=\${MINIO_SECRET_KEY:=password}
		export MINIO_ROOT_USER=\${MINIO_ACCESS_KEY:=admin}
		export MINIO_ROOT_PASSWORD=\${MINIO_SECRET_KEY:=password}
		export MINIO_CACHE_DRIVES="${CACHE_LIST:1}"
		export MINIO_STORAGE_CLASS_STANDARD="EC:2"
	        minio server\
			http://172.20.2.11:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} \
			http://172.20.2.13:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} \
			http://172.20.2.15:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} \
			http://172.20.2.17:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} \
			http://172.20.2.19:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} \
			http://172.20.2.41:9000$MNT_TOP_DIR/$MNT_STORE_PREFIX{$disk_1...$disk_n} #2>&1 >>/var/log/minio.log
	SCRIPT
	chmod a+x $MINIO_SERVER_SCRIPT
	printf "done\n To Start MinIO server: $(realpath $MINIO_SERVER_SCRIPT)\n\n"
}
do_minio_with_xfs_cache_setup() {
	DirCleanUp
	DirSetUp
	XfsCacheDiskPrep
	XfsWithCacheStorageDiskPrep
	MountCachedXFSStorageFileSystems
	CreateMinioLauncher
}
do_minio_disk_prep() {
	DirCleanUp
	DirSetUp
	StorageDiskPrep
	MountStorageFileSystems
	CreateMinioLauncher
}
#	do_minio_disk_prep
do_minio_with_xfs_cache_setup
