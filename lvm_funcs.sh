set -e
DRY_RUN=0
GO_SLOW=0

EVANS_SCSI_PREFIX='scsi-35000c500a'
MACH2_SCSI_PREFIX='scsi-36000c500a'
NYTRO_SCSI_PREFIX='scsi-35000c5003'
MACH2_WWN_PREFIX='wwn-0x6000c500a'
EVANS_WWN_PREFIX='wwn-0x5000c500a'
TATSU_WWN_PREFIX='wwn-0x5000c5009'
NYTRO_WWN_PREFIX='wwn-0x5000c5003'

#Use wwn version...
MACH2=$MACH2_WWN_PREFIX
EVANS=$EVANS_WWN_PREFIX
TATSU=$TATSU_WWN_PREFIX


LVM_STRIPE_SIZE=4 #k bytes
INC_LVM_STRIPE_SIZE=1 #k if non-zero, double  strpe size with each volume created
#DISK_READ_AHEAD=131072
OSD_READ_AHEAD=4096
#OSD_SCHEDULER='noop'
OSD_SCHEDULER='deadline'
DSK_PATH='/dev/disk/by-id'
LVM_VG_PREFIX='ceph'
LVM_LV_PREFIX='osd'
WCE=0  # Set Write Cache Enable

TOOL_REQUIREMENTS="sdparm lsscsi lvs pvs sg_vpd sg_ses sg_inq"

# Simple message output
msg() {
	printf "$@\n" 
	[[ $GO_SLOW == 1 ]] && sleep 1
	return 0
}
err() {
	printf "$@\n" 
	[[ $GO_SLOW == 1 ]] && sleep 1
	exit 1
}

# Run a command but first tell the user what its going to do.
run() {
	printf " $@ \n"
	[[ 1 == $DRY_RUN ]] && return 0
	eval "$@"; ret=$?
	[[ $ret == 0 ]] && return 0
   	printf " $@ - ERROR_CODE: $ret\n"
	exit $ret
}
check_for_tools() {
	for TOOL in $@
	do
		if [[ ! $(which $TOOL) ]]
		then	
			err "Could not find $TOOL installed"
		else
			msg "Have $TOOL"
		fi
	done
}
enclosure_sg=$(lsscsi -g  | grep enclos | grep SEAGATE | awk '{ print $7 }' | tail -1)

find_real_block_device() {
	basename $(readlink -m $1)
}

map_disk_slots() { 
	for dev in $(ls /dev/disk/by-id/ | grep "$1" | grep -v part) 
	do
		d="/dev/disk/by-id/$dev"
		this_sn=$(sg_vpd --page=0x80 $d \
		  | grep 'Unit serial number:' \
		  | awk -F ' ' '{print $4}')
		sas_address=$(sg_vpd --page=0x83 ${d} \
		  | grep -A 3 'Target port:' \
		  | grep "0x" | tr -d ' ' \
		  | cut -c 3-)
		device_slot=$(sg_ses -p 0xa ${enclosure_sg} \
		  | grep -B 8 -i $sas_address  \
		  | grep 'device slot number:'  \
		  | sed 's/^.*device slot number: //g')
		device_slot=$(printf "%03d" $device_slot)
		device_product=$(sg_inq $d \
		  | grep "Product identification" \
		  | sed 's/ Product identification: *//g' \
		  | sed 's/ //g')
		device_revision=$(sg_inq $d \
		  | grep "Product revision level:" \
		  | sed 's/ Product revision level: *//g' \
		  | sed 's/ //g')
		kdev=$(readlink -f $d)
		echo "    slot=$device_slot $dev sas_addr=$sas_address s/n=$this_sn $kdev $device_product $device_revision"
	done
}
build_disk_maps() {
	echo "Building Disk Maps..."
	for DSK_TYPE in MACH2 EVANS TATSU
	do
		DSK_PREFIX="${!DSK_TYPE}"
		echo "  $DSK_TYPE ($DSK_PREFIX):"
		map_disk_slots "${DSK_PREFIX}" | sort > ${DSK_TYPE}.map
	done
	EVANS_DRV_COUNT="$(cat EVANS.map | awk -F ' ' '{print $1}' | sort -u | wc -l)"
	MACH2_DRV_COUNT="$(cat MACH2.map | awk -F ' ' '{print $1}' | sort -u | wc -l)"
	TATSU_DRV_COUNT="$(cat TATSU.map | awk -F ' ' '{print $1}' | sort -u | wc -l)"
}
mk_striped_lvm() {
	SLOT=$1
	STRIPE_SIZE=$2
	DSK0=$3
	DSK1=$4
	LVM_LV_PREFIX="$5"
	msg "Making striped LVM on slot $SLOT DSK:$DSK1 DSK:$DSK2 STRIPE:$STRIPE_SIZE"
	if [[ $# < 4 ]]; then
		err "mk_striped_lvm Must supply slot, dsk1, dsk2 stripe_size"
	fi
	VG_NAME="${LVM_VG_PREFIX}_data_${SLOT}"
	LV_NAME="${LVM_LV_PREFIX}_data_${SLOT}_${STRIPE_SIZE}"
	run "    pvcreate $DSK0 $DSK1"
	run "    vgcreate --physicalextentsize 8M $VG_NAME $DSK0 $DSK1"
	run "    lvcreate -y -i 2 -n $LV_NAME -l 100%FREE --type striped -I $STRIPE_SIZE $VG_NAME"
}
mk_disk_lvm() {
	SLOT=$1
	DSK0=$2
	LVM_LV_PREFIX="EVANS"
	msg "Making disk LVM on slot $SLOT DSK:$DSK0"
	if [[ $# < 2 ]]; then
		err "mk_striped_lvm Must supply slot, dsk0"
	fi
	VG_NAME="${LVM_VG_PREFIX}_data_${SLOT}"
	LV_NAME="${LVM_LV_PREFIX}_data_${SLOT}"
	run "    vgcreate ${VG_NAME} ${DSK0}"
	run "    lvcreate -y -n ${LV_NAME} -l 100%FREE ${VG_NAME}"
}

rm_vg_devs() {
	msg "Purging volume groups"
	for VG in $(ls  /dev/${LVM_VG_PREFIX}*/* 2>/dev/null)
	do
		wipefs -a ${VG}
	done
	for VG in $( pvs | grep "${LVM_VG_PREFIX}" | awk '{print $2}' | sort -u)
	do
		PVS=$( pvs | grep $VG | awk '{ print $1 }'| tr '\n' ' ')
		msg "PVS=$PVS"
		run "   vgremove -y $VG"
		run "   pvremove -y $PVS"
	done
}
set_drv_queue() {
	if [[ ! -b "/dev/${1}" ]]
	then
		err "$1 is not a block device"
	else
		run "echo '${OSD_SCHEDULER}' >/sys/block/${1}/queue/scheduler"       # noop, deadline, cfq
		run "echo '${OSD_READ_AHEAD}' >/sys/block/${1}/queue/read_ahead_kb" # Default = 4096
	fi
}
set_drv_wce() {
	DSKPATH="/dev/${1}"
	if [[ ! -b ${DSKPATH} ]]; then
		echo "$DSKPATH is not a valid disk path"
		exit 1
	fi
	currentWCE="$(sdparm -q -g WCE $DSKPATH | awk -F ' ' '{print $2}')"	
	echo -n  " $DSKPATH WCE=$currentWCE "
	if [[ $WCE != $currentWCE ]] ; then
		# Need to modify 
		echo -n " Changing to -> $WCE "
		if [[ "$WCE" == 1 ]] ; then
			run "sdparm -q -s WCE $DSKPATH"
		else
			run "sdparm  -q -c WCE $DSKPATH"
		fi
	else
		echo  "  "
	fi
}
find_vg_count() {
	lvs | grep ${LVM_VG_PREFIX} | wc -l
}

print_drv_inventory() {
	msg "Detected $EVANS_DRV_COUNT Evans drives"
	msg "Detected $MACH2_DRV_COUNT Mach2 drives"
	msg "Detected $NYTRO_DRV_COUNT Nytro drives"
	msg "Detected $TOTAL_DRV_COUNT Total Drives"
	msg "Detected $VG_COUNT Existing Volume Groups"
}
mk_nytro_lvm() {
	msg "Creating Nytro LVM config"
	IDX=0
	for DEV in $( find ${DSK_PATH} -name "${NYTRO_DSK_PREFIX}*" | cut -c 1-38 | sort -u ); do
		KDEV="$(ls -lah $DEV | awk -F '/' '{print $7}')"
		msg "  Working on $DEV -> $KDEV"
		set_drv_queue "${KDEV0}"
		run "    pvcreate /dev/$KDEV"

		IDX_STR=$(printf '%03d' $IDX)
		VG_NAME="${LVM_VG_PREFIX}_db_${IDX_STR}"
		LV_NAME="${LVM_LV_PREFIX}_db_${IDX_STR}"
		run "    vgcreate ${VG_NAME} /dev/${KDEV}"
		run "    lvcreate -y -n ${LV_NAME}_0 -L 700G ${VG_NAME}"
		run "    lvcreate -y -n ${LV_NAME}_1 -L 700G ${VG_NAME}"
		run "    lvcreate -y -n ${LV_NAME}_2 -L 700G ${VG_NAME}"
		run "    lvcreate -y -n ${LV_NAME}_3 -L 700G ${VG_NAME}"
		run "    lvcreate -y -n ${LV_NAME}_X -L 700G ${VG_NAME}"
		IDX=$( expr $IDX + 1 )
	done
	msg "Success!"
}
mk_mach2_lvms() {
	if [[ $MACH2_DRV_COUNT == 0 ]] ; then
		truncate -s 0 LVM_mach2.map
		return
	fi
	for SLOT in $(cat MACH2.map | grep slot | sed 's/=/ /g' | awk -F ' ' '{print $2}' | sort -u)
	do
		DSK0=$(cat MACH2.map | grep slot="$SLOT" | grep "000000000000000" | awk -F ' ' '{print $2}')
		DSK1=$(cat MACH2.map | grep slot="$SLOT" | grep "001000000000000" | awk -F ' ' '{print $2}')
		KDEV0=$(basename $(cat MACH2.map | grep slot="$SLOT" | grep 000000000000000 | awk -F ' ' '{print $5}'))
		KDEV1=$(basename $(cat MACH2.map | grep slot="$SLOT" | grep 001000000000000 | awk -F ' ' '{print $5}'))
		run "wipefs -a /dev/$KDEV0"
		run "wipefs -a /dev/$KDEV1"
		set_drv_queue $KDEV0
		set_drv_queue $KDEV1
		set_drv_wce $KDEV0
		set_drv_wce $KDEV1
		mk_striped_lvm $SLOT ${LVM_STRIPE_SIZE}k /dev/disk/by-id/$DSK0 /dev/disk/by-id/$DSK1 "MACH2"
		if [[ $INC_LVM_STRIPE_SIZE == 1 ]]; then
			LVM_STRIPE_SIZE=$((LVM_STRIPE_SIZE * 2))
		fi
	done
	lvdisplay | grep 'LV Path' | grep ${LVM_VG_PREFIX} | sort | awk -F ' ' '{print $3}' | tee LVM_mach2.map
}
mk_evans_lvms() {
	if [[ $EVANS_DRV_COUNT == 0 ]] ; then
		truncate -s 0 LVM_evans.map
		return
	fi
	for SLOT in $(cat EVANS.map | grep slot | sed 's/=/ /g' | awk -F ' ' '{print $2}' | sort -u)
	do
		DSK0=$(cat EVANS.map | grep slot="$SLOT" | awk -F ' ' '{print $2}')
		KDEV0=$(basename $(cat EVANS.map | grep slot="$SLOT" | awk -F ' ' '{print $5}'))
		set_drv_queue $KDEV0
		set_drv_wce $KDEV0
		run "wipefs -a /dev/$KDEV0"
		mk_disk_lvm $SLOT /dev/disk/by-id/$DSK0
	done
	lvdisplay | grep 'LV Path' | grep ${LVM_VG_PREFIX} | sort | awk -F ' ' '{print $3}' | tee LVM_evans.map
}
mk_evans_paired_lvm() {
	if [[ $EVANS_DRV_COUNT == 0 ]] ; then
		truncate -s 0 LVM_evans.map
		return
	fi
	while read -r SLOT_A
	do
		read -r SLOT_B
		DSK0="$(echo $SLOT_A  | awk -F ' ' '{print $2}' | sed 's/ //g')"
		DSK1="$(echo $SLOT_B  | awk -F ' ' '{print $2}' | sed 's/ //g')"
		KDEV0="$(echo $SLOT_A  | awk -F ' ' '{print $5}' | sed 's/ //g' | awk -F '/' '{print $3}')"
		KDEV1="$(echo $SLOT_B  | awk -F ' ' '{print $5}' | sed 's/ //g' | awk -F '/' '{print $3}')"
		SLOT0="$(echo $SLOT_A  | sed 's/=/ /g' | awk -F ' ' '{print $2}' | sed 's/ //g')"
		SLOT1="$(echo $SLOT_B  | sed 's/=/ /g' | awk -F ' ' '{print $2}' | sed 's/ //g')"
		run "wipefs -a /dev/$KDEV0"
		run "wipefs -a /dev/$KDEV1"
		set_drv_queue $KDEV0
		set_drv_queue $KDEV1
		set_drv_wce $KDEV0
		set_drv_wce $KDEV1
		mk_striped_lvm "${SLOT0}_${SLOT1}" ${LVM_STRIPE_SIZE}k /dev/disk/by-id/$DSK0 /dev/disk/by-id/$DSK1 "EVANS"
		if [[ $INC_LVM_STRIPE_SIZE == 1 ]]; then
			LVM_STRIPE_SIZE=$((LVM_STRIPE_SIZE * 2))
		fi
	done<EVANS.map
	lvdisplay | grep 'LV Path' | grep ${LVM_VG_PREFIX} | sort | awk -F ' ' '{print $3}' | tee LVM_evans_paired.map
}

mk_lvms() {
	check_for_tools $TOOL_REQUIREMENTS
	build_disk_maps
	print_drv_inventory
	rm_vg_devs
	#mk_mach2_lvms | tee LVM_MACH.log
	#mk_evans_lvms | tee LVM_EVANS.log
	#mk_evans_paired_lvm | tee LVM_EVANS.log
}
mk_lvms
