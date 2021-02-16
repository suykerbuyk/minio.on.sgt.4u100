#!/bin/sh


declare -a SERVER_NODES

ACCESS_KEY="admin"
SECRET_KEY="password"
SERVER_NODES=( 4u100-1a 4u100-1b 4u100-2a 4u100-2b 4u100-3a 4u100-3b )
SERVER_HOSTS="172.20.2.10:9000,172.20.2.12:9000,172.20.2.14:9000,172.20.2.16:9000,172.20.2.18:9000,172.20.2.40:9000"
CLIENT_HOSTS="172.20.2.50:8000,172.20.2.52:8000,172.20.2.54:8000,172.20.2.56:8000"

declare -a SCHEDULERS 
SCHEDULERS=("none" "mq-deadline" "kyber" "bfq")


prep_for_testing() {
	for NODE in "${SERVER_NODES[@]}"
	do
		echo "Copying testmon to ${NODE}"
		scp ./testmon.sh root@${NODE}:/root/
		scp ./SetDiskScheduler.sh root@${NODE}:/root/
		ssh root@${NODE} "chmod +x /root/testmon.sh"
		ssh root@${NODE} "rm -f /root/*.log"
	done
}

sysmonitor_stop() {
	for NODE in "${SERVER_NODES[@]}"
	do
		echo "Stopping monitor on ${NODE}"
		ssh root@${NODE} "/root/testmon.sh stop dummy"
		rsync -v --remove-source-files root@${NODE}:\*.log .

	done
}
sysmonitor_start() {
	name="${1}"
	for NODE in "${SERVER_NODES[@]}"
	do
		echo "Starting monitoring on ${NODE}"
		echo ssh root@${NODE} "/root/testmon.sh start ${TEST_NAME}"
		ssh root@${NODE} "/root/testmon.sh start ${TEST_NAME}" &
	done
}
set_disk_scheduler() {
	for NODE in "${SERVER_NODES[@]}"
	do
		ssh root@${NODE} "/root/SetDiskScheduler.sh $1"
	done
}

#for OBJ_SIZE in 128KiB 512KiB 1MiB 8MiB 16MiB 32MiB 64MiB 128MiB
prep_for_testing

for OBJ_SIZE in $((128 * 1024)) \
		$((512 * 1024)) \
		$((1 *   1024 *1024)) \
		$((4 *   1024 *1024)) \
		$((16 *  1024 *1024)) \
		$((64 *  1024 *1024))
do
	echo "Object Size = ${OBJ_SIZE}"
	for CONC in 8 16 24 48 64 96 128
	#for CONC in 128 96 48 24 16  8
	do
		CONC_STR=$(printf "%03d" $CONC)
		
		#for OP in put get mixed delete
		for OP in put get
		do
			for SCH in ${SCHEDULERS[*]};
			do
				echo "================================="
				set_disk_scheduler $SCH
				TEST_NAME="${OP}-${CONC_STR}-${OBJ_SIZE}-${SCH}"
				DEL_OBJS=$(($CONC * 400))
				OPTIONS=" "
				OPTIONS="${OPTIONS} --access-key=${ACCESS_KEY} "
				OPTIONS="${OPTIONS} --secret-key=${SECRET_KEY} "
				OPTIONS="${OPTIONS} --host=${SERVER_HOSTS} "
				OPTIONS="${OPTIONS} --warp-client=${CLIENT_HOSTS} "
				OPTIONS="${OPTIONS} --obj.size=${OBJ_SIZE} "
				OPTIONS="${OPTIONS} --benchdata=${TEST_NAME} "
				OPTIONS="${OPTIONS} --duration=7m30s "
				OPTIONS="${OPTIONS} --concurrent=${CONC} "
				OPTIONS="${OPTIONS} --autoterm --autoterm.dur=20s "
				OPTIONS="${OPTIONS} --quiet --noclear "
				echo "Starting ${TEST_NAME}"
				sysmonitor_start "${TEST_NAME}"
				echo "Launching Warp"	
				# 1000 objectes * 4 servers * number of threads
				case ${OP} in 
					"delete")
						OPTIONS="delete ${OPTIONS} --objects=${DEL_OBJS} "
						;;
					*)
						OPTIONS="${OP} ${OPTIONS}"
						;;
				esac
				echo "warp ${OPTIONS}"
				warp ${OPTIONS}
				sysmonitor_stop
				echo "Completed ${TEST_NAME}"
				echo "---------------------------------"
			done
		done
	done
done
