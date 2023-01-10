#!/bin/bash

# Original script by Kirk https://github.com/kirrrk/scripts/blob/main/slowkills.sh
# Modified script to work on multiple containers Carey https://github.com/careydayrit/locum
# environment is live server

# USAGE:
# ./site-slow-kills.sh <site_id>

# Exit on error
set -e

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

if [ -z "$1" ]; then
    echo "Site ID empty"
    exit
fi

CHECKSITE_ID=$(echo $1 | grep '^[a-zA-Z0-9]\{8\}[ -][a-zA-Z0-9]\{4\}[ -][a-zA-Z0-9]\{4\}[ -][a-zA-Z0-9]\{4\}[ -][a-zA-Z0-9]\{12\}$')

if [ -z ${CHECKSITE_ID} ]; then
	echo "Site ID invalid"
	exit 1
fi

if [[ ! -d reports ]]; then
	mkdir reports
fi

# Fetch the username on ~/.ssh/config
USERNAME="`ssh -G yggdrasil.us-central1.panth.io | grep 'user ' | awk -F' ' '{ print $2 }' | xargs`"

# make the search date as the server time (UTC)
SEARCHDATE=`date -u +"%d-%b-%Y"`

# check if there is jq
if ! [ -x "$(command -v jq)" ]; then
	echo 'Error: The jq command was not found. Please install it yourself and try again.' >&2
	exit 1
fi

# site data binding and conneciton info
ssh $USERNAME@`dig +short yggdrasil.us-central1.panth.io | tail -1` "/usr/local/bin/ygg sites/$1/bindings  --silent" > ./reports/$1.bindings.json

# produce this string
while read -r value; do
	servers+=("$value")	
done < <(cmd file | ./reports/"$1".bindings.json | jq -r '.[] | select(.environment=="live") | select(.type=="appserver") | select(.failover!=true) | "" + .host + " " + .id' )

echo "Downloading logs"

# fetch data
for server in "${servers[@]}"; do
	info=($server)
	ssh-keyscan -p 2225 -H "${info[0]}" >> ~/.ssh/known_hosts
	rsync -rlvz --size-only --ipv4 --progress -e "ssh -p 2225" "${USERNAME}@${info[0]}:/srv/bindings/${info[1]}/logs/php" "./reports/app_server_${info[1]}"		
done
clear
for server in "${servers[@]}"; do
	info=($server)
	KILLED=`grep $SEARCHDATE.\*SIGKILL "./reports/app_server_${info[1]}/php/php-fpm-error.log" | awk '{print $7}' | sort`
	SLOW=`grep $SEARCHDATE.\*pool\ www "./reports/app_server_${info[1]}/php/php-slow.log" | awk '{print $6}' | sort`
	SLOWKILLED=`comm -1 -2 <(echo "$KILLED") <(echo "$SLOW")`
	echo "App Server ${info[0]}"
	if [ -z "$SLOWKILLED" ]; then
		echo "No matches."
		echo  
		continue
	fi
	
	# Iterate throught the matching PIDs, output the corresponding line from the error log with the corresponding block from the slow log.
	while IFS= read -r line; do
		grep $SEARCHDATE.\*child\ $line\ .\*SIGKILL "./reports/app_server_${info[1]}/php/php-fpm-error.log"
		sed -n "/$SEARCHDATE.*pid $line$/,/^$/p" "./reports/app_server_${info[1]}/php/php-slow.log"
	done <<EOF
$SLOWKILLED
EOF
	echo 
	echo `comm -1 -2 <(echo "$KILLED") <(echo "$SLOW") | wc -l` matches found.
	echo `diff -u <(echo "$KILLED") <(echo "$SLOW") | grep '^-[^-]' | wc -l` killed processes did not match PIDs found in the php-slow logs.
	echo
done
