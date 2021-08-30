#!/bin/bash

DISKNUM=1
NUMPARTS=16
PARTLIST=""
let FSCOUNT=`wc -l config/disks | awk '{ print $1 }'`

#
# Generic setup for all filesystem types.
#
setup()
{
	rm /tmp/mounted
	FSCOUNT=$((${FSCOUNT} * ${NUMPARTS}))
	for mtpt in `seq 1 ${FSCOUNT}`
	do
		umount /aim7_${mtpt}
	done
	rm disk_config
	mkdir /aimrun
	cp config/disks_use /aimrun/disks
	for disk in `cat config/disks_use`; do
		wipefs -a ${disk}
		parted -a optimal ${disk} mklabel gpt
		sleep 1 # Because for some stupid reason otherwise partitions randomly don't get recognized
		startpct=0
		endpct=0
		for part in `seq 1 ${NUMPARTS}`; do
			echo "/aim7_${DISKNUM}" >> disk_config
			partname=${disk}p${part}
			endpct=$((100 / ${NUMPARTS} * ${part}))
			parted -a optimal ${disk} mkpart primary $1 ${startpct}% ${endpct}%
			sleep 1 # Because for some stupid reason otherwise partitions randomly don't get recognized
			export disk
			mkdir /aim7_${DISKNUM} >& /dev/null
			DISKNUM=`expr $DISKNUM + 1`
			startpct=${endpct}
			sleep 1 # Because for some stupid reason otherwise partitions randomly don't get recognized
		done
	done
	#
	# Reset DISKNUM back to 1, so that in the fs specfic code we use the appropriate
	# device and directory.
	#
	DISKNUM=1
}

#
# Check the mounted filesystems, did everything work right?
#
mount_check()
{
	let FSCOUNT=`wc -l config/disks_use | awk '{ print $1 }'`
	FSCOUNT=$((${FSCOUNT} * ${NUMPARTS}))
	HOSTNAME=`/bin/hostname -s`
	PERFMOUNTED=`mount -l | grep 'aim7_[0-9]' | grep -v ${HOSTNAME} | wc -l`
	if [ $PERFMOUNTED -ne $FSCOUNT ]; then
    		echo "`date` - NOT ALL FILE SYSTEMS MOUNTED"
    		df | grep aim7_ | wc -l
    		sleep 999999999
	fi
}

#
# gfs2 filesystem setup
#
gfs2_creation()
{
	for disk in `cat config/disks_use`; do
		for part in `seq 1 ${NUMPARTS}`; do
			partname=${disk}p${part}
        		mkfs -t gfs2  -O -p lock_nolock -j 1 -t notaclu:${partname} ${partname} 
			mount -t gfs2 -o noatime,nobarrier,loccookie  ${partname} /aim7_$DISKNUM
        		DISKNUM=`expr $DISKNUM + 1`
    		done 
	done
	mount_check
}

#
# ext3 filesystem setup
#
ext3_creation()
{
	setup ext3
	for disk in `cat config/disks_use`; do
		for part in `seq 1 ${NUMPARTS}`; do
			partname=${disk}p${part}
			mkfs -F -t ext3 ${partname}
			mount -t ext3 ${partname} /aim7_$DISKNUM
			DISKNUM=`expr $DISKNUM + 1`
		done 
	done
	mount_check
}

#
# ext4 filesystem setup
#
ext4_creation()
{
	setup ext4
	for disk in `cat config/disks_use`; do
		for part in `seq 1 ${NUMPARTS}`; do
			partname=${disk}p${part}
			mkfs -F -t ext4 ${partname}
			mount -t ext4 ${partname} /aim7_$DISKNUM
        		DISKNUM=`expr $DISKNUM + 1`
		done
	done 
	mount_check
}

#
# xfs filesystem setup
#
xfs_creation()
{
	setup xfs
	for disk in `cat config/disks_use`;do
		for part in `seq 1 ${NUMPARTS}`; do
			partname=${disk}p${part}
			mkfs -t xfs -K -f ${partname}
			mount -t xfs ${partname} /aim7_$DISKNUM
			DISKNUM=`expr $DISKNUM + 1`
		done 
	done
	mount_check
}

#
# Define options
#

NUMPARTS=16
ARGUMENT_LIST=(
	"filesys_type"
	"partitions"
)

NO_ARGUMENTS=(
	"usage"
)

# read arguments
opts=$(getopt \
    --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
    --longoptions "$(printf "%s," "${NO_ARGUMENTS[@]}")" \
    --name "$(basename "$0")" \
    --options "h" \
    -- "$@"
)

eval set --$opts

while [[ $# -gt 0 ]]; do
	case "$1" in
		--filesys_type)
			filesys_type=$2
			shift 2
		;;
		--partitions)
                        NUMPARTS=$2
                        shift 2
                ;;
		--usage)
			echo later
			exit
		;;
		--)
			break
		;;
		*)
			echo "option $1 not found"
			exit
		;;
        esac
done

#
# Build the appropriate filesystem
#
if [ $filesys_type == "xfs" ]; then
	xfs_creation
fi

if [ $filesys_type == "ext3" ]; then
	ext3_creation
fi

if [ $filesys_type == "ext4" ]; then
	ext4_creation
fi

if [ $filesys_type == "gfs2" ]; then
	dnf install -y gfs2-utils.x86_64
	gfs2_creation
fi

