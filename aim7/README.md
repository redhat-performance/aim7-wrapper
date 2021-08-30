This is a repository for the AIM 7 workload.  Included in here are
   a) Various fixes located during use by the RH performance team
   b) Predefined configuration files.  They do not approach cross over due to the time it takes.
      Instead the load generated should be enough to catch the majoirty of the performance issues.
   c) data_gather script: Retreives various system statistics for future reference
   d) aimit.sh: script that performs the setup of the environment and then runs the test.  Options are
   -d <STANRDARD/NVME>: drive type
   -h help message
   -u <unique name>: a unique name to tag to the end
   -f <filesystems>: xfs ext4 ext3 gfs2
   -i <input file>: input file \(load\) to use
   -p run as part of pbench
   -w <workload list>: fserver compute shared dbase

