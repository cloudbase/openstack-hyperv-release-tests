#!/bin/bash
set -e

BASEDIR=$(dirname $0)

. $BASEDIR/utils.sh

host=$1
win_user=Administrator
win_password=Passw0rd

if [ -z "$host" ]; then
    echo "Usage: $0 <host>"
    exit 1
fi

reboot_win_host $host

