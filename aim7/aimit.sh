#!/bin/bash

fields=`echo $0 |awk -F'/' '{print NF}'`
let fields="$fields-1"
wdir=`echo $0 | cut -d'/' -f1-$fields`
cd $wdir

PATH=`pwd`/bin:$PATH
export PATH

./bin/aimit.sh "$@"

