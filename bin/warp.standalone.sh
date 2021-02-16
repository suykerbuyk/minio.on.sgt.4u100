#!/bin/sh

for OBJSIZE in 10KiB 100KiB 1MiB 10MiB 100MiB
do
	for CONC in 8 16 24 48 96 128
	do
		for OP in put get mixed
		do
			warp ${OP} \
			   --host=172.20.2.12:80,172.20.2.16:80,172.20.2.40:80\
			   --quiet\
			   --obj.size=${OBJSIZE}\
			   --autoterm\
			   --concurrent=${CONC}\
			   --access-key=5BLC7WUZ69OOS4LRHLM9\
			   --secret-key=Hc8nAbbC4D3ZXNFmrhBrzzscBa5yAcamsM3UKlwI | tee ${OP}-${OBJSIZE}-${HOSTNAME}-${CONC}.log
		done
	done
done
