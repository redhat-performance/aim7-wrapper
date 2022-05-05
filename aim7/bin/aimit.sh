#!/bin/bash 
#
#                         License
#
# Copyright (C) 2021  David Valin dvalin@redhat.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# aimit.sh: automate the aim7 run
#

arguments="$@"
fields=`echo $0 |awk -F'/' '{print NF}'`
let fields="$fields-2"

if [[ $0 == "./"* ]]; then
	run_dir=`pwd`
else
	chars=`echo $0 | awk -v RS='/' 'END{print NR-1}'`
	run_dir=`echo $0 | cut -d'/' -f 1-${chars}`
fi

aim_exec=$0
 
#
# Default values
#
WORKLOADS="compute,dbase,fserver,shared"
DRVTYPE="NVME"
FSLIST="xfs,ext4,ext3,gfs2"
UNIQ=""
disks="none"
BASE=/aim_data
PARTITIONS=16
dynamic_size=0
CAP_INC=200
GFS_CAP_INC=50
custom_config="none"
passed_config="none"
config="none"
tools_git=https://github.com/redhat-performance/test_tools-wrappers

usage()
{
	echo Usage ${1}:
	echo "--custom_config <string>:  designates the load to run.  Format is a semi-colon separated list"
	echo "  <start>-<end>x<increment>;....."
	echo "  Example: --custom_config \"1-1x1,100-900x100;1000-44000x1000\""
	echo "--disks <disks>: ',' separated list of disks to use."
	echo "--dynamic_size: will dynamically cap the max number users to run.  Calc is 2k times # cpus."
	echo "    Default is to use the regular config file"
	echo "--filesystem <filesystems>: ',' separated list of filesystems."
	echo "    currently supported xfs ext4 ext3 gfs2"
	echo "--load_file <load file prefix>: aim load file prefix to use"
	echo "--partitions <# disk partitions/disk>"
	echo "--usage: help message"
	echo "--workload <workload list>: semi-colon separated list of workloads with possible loads"
	echo "    known values fserver compute shared dbase"
	echo "    Examples"
	echo "      Example 1: straight multiple workloads"
	echo "          --workload  compute;shared;fsever"   
	echo "      Example 2: multiple workloads with differing loads"
	echo "          --workload  compute:1-1x1;100-900x100;1000-44000x1000,shared:1-1x1;100-900x100;1000-20000x1000"   
	source test_tools/general_setup --usage
}

#
# Standard location to pull the test_tools from.
#
# Variables set
#
# TOOLS_BIN: points to the tool directory
# to_home_root: home directory
# to_configuration: configuration information
# to_times_to_run: number of times to run the test
# to_pbench: Run the test via pbench
# to_puser: User running pbench
# to_run_label: Label for the run
# to_user: User on the test system running the test
# to_sys_type: for results info, basically aws, azure or local
# to_sysname: name of the system
# to_tuned_setting: tuned setting
#
tools_git=https://github.com/dvalinrh/test_tools

#
# Clone the repo that contains the common code and tools
#
found=0
for arg in "$@"; do
	if [ $found -eq 1 ]; then
		#
		# Different test_tools location designated.
		#
		tools_git=$arg
		break;
	fi
	if [[ $arg == "--tools_git" ]]; then
		found=1
	fi
	if [[ $arg == "--usage" ]]; then
		#
		# Usage request present.  Note do not exit out, we will do that
		# in test_tools/general_setup
		# 
		usage $0
	fi
done

if [ ! -d "test_tools" ]; then
	#
	# Clone the tools if required.
	#
        git clone $tools_git
        if [ $? -ne 0 ]; then
                echo pulling git $tools_git failed.
                exit
        fi
fi
#
# Perfrom the general test setup.
#
# If using getops, it has to appear after this.
#
source test_tools/general_setup "$@"

cd $run_dir

#
# set up the disks to use.
#
set_disks()
{
	if [[ $disks == "none" ]]; then
		cp config/disks config/disks_use
	else
		rm  config/disks_use
		if  [[ $disks == "grab_disks" ]]; then
			$TOOLS_BIN/grab_disks grab_disks
			for i in `cat disks`; do
				echo  /dev/${i} >> config/disks_use
			done
		else
			disk_list=`echo $disks | sed "s/,/ /g"`
			for i in $disk_list; do
				echo  $i >> config/disks_use
			done
		fi
	fi
	cp config/disks_use config/disks
}

dynamic_size_config()
{
	#
	# Size based on number of CPUs, gap for gfs2
	#
	# Get the number of cpus and then calc the max workload value.
	#
	lscpu > /tmp/lscpu.tmp
	on_line=`grep ^CPU\(s\): /tmp/lscpu.tmp | cut -d':' -f 2`
	if [ $2 != "gfs2" ]; then
		max_cap=`echo "(($on_line*$CAP_INC+999)/1000)*1000" | bc`

		if [ $max_cap -gt 44000 ]; then
			max_cap=44000
		fi
	else
		let "max_cap=$on_line*$GFS_CAP_INC"
		max_cap=`echo "(($on_line*$GFS_CAP_INC+999)/1000)*1000" | bc`
		if [ $max_cap -gt 2000 ]; then
			max_cap=2000
		fi
	fi
	cat config/input_files/dynamic/input.$1 | sed "s/REPLACE/$max_cap/g" > config/input.$1
}

build_custom_config()
{
	custom_value=$2
	nitems=0
	list=`echo $custom_value | sed "s/;/ /g"`
	for i in $list; do
		let "nitems=$nitems+1"
	done
	echo redeye > config/input.$1
	echo red >> config/input.$1
	echo $nitems >> config/input.$1
	for i in $list; do
		# 1-1x1
		echo $i | cut -d'-' -f 1 >> config/input.$1
		echo 2 >> config/input.$1
		last_fields=`echo $i | cut -d'-' -f2`
		echo $last_fields | cut -d'x' -f 1 >> config/input.$1
		echo $last_fields | cut -d'x' -f 2 >> config/input.$1
	done	
}

set_config_file()
{

	built=0
	rm -rf config/input.*
	if [[ $passed_config != "none" ]]; then
		built=1
		build_custom_config $1 $passed_config
	fi
	if [[ $built -eq 0 ]] && [[ $dynamic_size -eq 1 ]]; then
		built=1
		dynamic_size_config $1 $2
	fi
	if [[ $built -eq 0 ]] && [[ $custom_config != "none" ]]; then
		built=1
		build_custom_config $1 $custom_config
	fi
	if [ $built -eq 0 ]; then
		cp config/input_files/default/input.$1 config
	fi
}

#
# Set system values
#
set_sys_values()
{
	ulimit -s unlimited
	ulimit -l 16000000
	ulimit -u unlimited
	ulimit -n 32000
	#
	# Fix for shared memory
	#
	echo 32000 > /proc/sys/kernel/shmmni
	#
	# Adjust for udp
	#
	echo 10000 > /proc/sys/net/core/netdev_max_backlog

	sysctl -w kernel.shmmax=68719476736000
	sysctl -w kernel.shmall=4294967296000
	sysctl -w kernel.sem="25000      3200000   32000      12800"
	sysctl -w net.core.rmem_max=26214400
	sysctl -w net.unix.max_dgram_qlen=2048
	sysctl -w kernel.pid_max=1280000
	systemctl daemon-reload
}


#
# Execute the actual workload.
#
execute_workload()
{
	WL=$1
	FS=$2

	echo ""
	echo "`date` - SETUP OF RUN:  Workload: $WL  Filesystem: $FS"
	RES_PATHNAME=${BASE}/${TDIR}/${WL}

	HOSTNAME=`/bin/hostname -s`

	echo "`date` - MAKE FILESYSTEMS"
	init_disks.sh --filesys_type $FS --partitions $PARTITIONS
	echo "`date` - MOUNT -l SAMPLE FILESYSTEM FLAGS"
	mount -l | grep -w aim7_
	#
	# Show the mount points.
	#
	echo "`date` - /proc/mounts SAMPLE MOUNT FLAGS"
	grep -w aim7_ /proc/mounts

	rm -f ${BASE}/workfile ${BASE}/input
	cp config/workfile.${WL} ${BASE}/workfile
	if [[ -z ${INPUT} ]] ; then
		cp config/input.${WL} ${BASE}/input
		echo ${INPUT}
	else	
		echo ${INPUT}
		cp ${INPUT} ${BASE}/input
	fi
	mv disk_config ${BASE}/config
	cp config/fakeh.tar ${BASE}/fakeh.tar

	pushd $BASE

	echo "`date` - VMSTAT STARTED"
	vmstat 1 > ${RES_PATHNAME}/${FS}_vmstat.txt 2>&1 &
	VPID=$!
	sleep 3
	echo "`date` - CACHE DROP"
	echo 3 > /proc/sys/vm/drop_caches
	sleep 10

	echo "`date` - START RUN"
	
	nohup RUN > ${RES_PATHNAME}/${FS}_aim7.txt &
	RPID=$!
	wait $RPID

	sleep 10
	kill $VPID
	popd
}

execute_fs()
{
	if [[ $1 = *":"* ]]; then
		wl=`echo $1 | cut -d: -f1`
		passed_config=`echo $1 | cut -d: -f2`
	else
		wl=$1
		passed_config="none"
	fi
	for FS in $FSLIST; do
		set_config_file $wl $FS $passed_config
		execute_workload $wl $FS
	done
}

produce_csv()
{
	tmpfile=$(mktemp /tmp/aim_reduce.XXXXXX)
	located=0
	header=0
	for dl1 in `ls -d aim7*`
	do
		pushd $dl1
		for dl2 in `ls -d *`
		do
			if [[ ! -d $dl2 ]]; then
				continue
			fi
			pushd $dl2
			file_look_for=`ls *aim7.txt`
			while IFS= read -r line
			do
				if [[ $located -le 1 ]]; then
					if [ $located -eq 1 ]; then
						located=2
					fi
					if [[ $line = *"Beginning"* ]]; then
						located=1
					fi
					continue
				fi
				if [[ -z $line ]]; then
					break;
				fi
				if [[ $line = *"Tasks"* ]] && [ $header -eq 1 ]; then
					continue
				fi
				header=1
				echo "${line}" >> ${tmpfile}
			done < "$file_look_for"
			cat $tmpfile | sed 's/[ ][ ]*/ /g' | sed 's/^ //g' | cut -d' ' -f 1,2,4-7 | sed 's/ /:/g' > results.csv
			popd
		done
		popd
	done
}

#
# Retrieve the arguments for the test.
#
ARGUMENT_LIST=(
	"custom_config"
	"disks"
	"filesystem"
	"load_file"
	"partitions"
	"run_name"
	"workload"
)

NO_ARGUMENTS=(
	"dynamic_size"
)

# read the options
opts=$(getopt \
    --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
    --longoptions "$(printf "%s," "${NO_ARGUMENTS[@]}")" \
    --name "$(basename "$0")" \
    --options "h" \
    -- "$@"
)

eval set --$opts

if [ $? -ne 0 ]; then
	exit
fi

while [[ $# -gt 0 ]]; do
	case "$1" in
		--custom_config)
			custom_config=$2
			shift 2
		;;
		--disks)
			disks=$2
			shift 2
		;;
		--dynamic_size)
			dynamic_size=1
			shift 1
		;;
		--filesystem)
			FSLIST=$2
			shift 2
		;;
		--load_file)
			INPUT=$2
			shift 2
		;;
		--partitions)
			PARTITIONS=$2
			shift 2
		;;
		--run_name)
			UNIQUE=$2
			shift 2
		;;
		--workload)
			WORKLOADS=$2
			shift 2
		;;
		--)
			break
		;;
		*)
			echo "option $1 not found"
			usage $0
		;;
	esac
done

if [ $to_pbench -eq 1 ]; then
        source ~/.bashrc

	#
	# Else we will run out of disk space!!!
	#
	if [ -f /var/lib/pbench-agent/tools-default/pidstat ]; then
		mv /var/lib/pbench-agent/tools-default/pidstat /root/pidstat_pbench
	fi
	if [ -f /var/lib/pbench-agent/tools-default/proc-interrupts ]; then
		mv /var/lib/pbench-agent/tools-default/proc-interrupts /root/proc-interrupts
	fi
	if [ -f /var/lib/pbench-agent/tools-default/perf ]; then
		mv /var/lib/pbench-agent/tools-default/perf /root/proc-interrupts
	fi
	if [ -f /var/lib/pbench-agent/tools-default/iostat ]; then
		mv /var/lib/pbench-agent/tools-default/perf /root/iostat
	fi
	echo $TOOLS_BIN/execute_via_pbench_1 --cmd_executing "$aim_exec" ${arguments} --test aim7 --spacing 11
	$TOOLS_BIN/execute_via_pbench_1 --cmd_executing "$aim_exec" ${arguments} --test aim7 --spacing 11
	if [ -f /root/pidstat_pbench ]; then
		mv /root/pidstat_pbench /var/lib/pbench-agent/tools-default/pidstat
	fi
	if [ -f /root/proc-interrupts ]; then
		mv /root/proc-interrupts /var/lib/pbench-agent/tools-default/proc-interrupts
	fi
	if [ -f /root/perf ]; then
		mv /root/perf /var/lib/pbench-agent/tools-default/perf
	fi
	if [ -f /root/iostat ]; then
		mv /root/perf /var/lib/pbench-agent/tools-default/iostat
	fi
else
	#
	# First build it.  Different archs.
	#
	pushd $run_dir/aim_src
	rm -f ../bin/multiask 2> /dev/null
	make
	popd
	cp bin/aim_1.sh /bin
	chmod 755 /bin/aim_1.sh
	set_sys_values
	set_disks

	#
	# Set up the values to run with
	#
	WORKLOADS=`echo $WORKLOADS | sed "s/,/ /g"`
	FSLIST=`echo $FSLIST | sed "s/,/ /g"`
	PATH=`pwd`/bin:$PATH
	PATH=${PATH}:${BASE}
	KERN=`uname -r | cut -c1`
	echo "`date` - FILESYSTEMS TESTED ARE: $FSLIST"
	mkdir $BASE

	#
	# set up results directory
	#

	TDIR=aim7-`uname -r`-`date '+%Y-%b-%d_%Hh%Mm%Ss'`-$UNIQ
	mkdir ${BASE}/${TDIR}
	cp /proc/cpuinfo ${BASE}/${TDIR}
	echo "`date` - TUNE SYSTEM RESOURCE FOR AIM FUNCTIONALITY"

	#
	# Execute the test.
	#
	rm -rf /tmp/results_aim7_${to_tuned_setting}
	mkdir /tmp/results_aim7_${to_tuned_setting}
	for WL in $WORKLOADS; do
		echo $WL
		wl=`echo $WL | cut -d: -f1`
    		mkdir -p ${BASE}/${TDIR}/${wl}
		execute_fs $WL
	done
	pushd /aim_data
	dir=`ls -td aim7* | head -n 1`
	cp -R $dir /tmp/results_aim7_${to_tuned_setting}/$TDIR
	popd

	cd /tmp/results_aim7_${to_tuned_setting}
	produce_csv
	cd ..
	tar cf results_aim7_${to_tuned_setting}.tar results_aim7_${to_tuned_setting}
	#
	# Unmount the filesystems.
	#
	umount /aim7_*
fi


#
# We are done, clean up the disks.
#
for disk in `cat config/disks_use`; do
	wipefs -a ${disk}
done
