#!/bin/bash

# This script outputs the sections of the php-slow log that match PIDs of php-fpm processes that were killed.
# The goal is to help identify slow php processes that may be causing 50x errors.
# The script only looks for matches on one date (today's date if no parameters are provided) to limit the output and hopefully prevent mismatching on reused PIDs.
#
# USAGE:
#  slowkills.sh [DATE] [ERROR LOG] [SLOW LOG]
#
# EXAMPLES:
#  slowkills.sh
#  slowkills.sh 01-Jun-2022
#  slowkills.sh 02-Jun-2022 logs/php/php-fpm-error.log logs/php/php-slow.log

SEARCHDATE=`date +"%d-%b-%Y"`
PHP_FPM_ERROR_LOG=php-fpm-error.log
PHP_SLOW_LOG=php-slow.log

if [ "$1" ]; then
  UNAME=$(uname)
  if [[ "$UNAME" == "Linux" ]]; then 
    SEARCHDATE=`date -d "$1" +"%d-%b-%Y"`
  else
    SEARCHDATE="$1"
  fi
fi

if [ "$2" ]; then
  PHP_FPM_ERROR_LOG="$2"
fi

if [ "$3" ]; then
  PHP_SLOW_LOG="$3"
fi

if [[ ! -f $PHP_FPM_ERROR_LOG ]] && [[ ! -f PHP_SLOW_LOG ]]
then
  echo "No php-fpm error logs or php-slow logs found."
  echo "Check that you are running the script from the correct location or modify the PHP_FPM_ERROR_LOG and PHP_SLOW_LOG variables to point to the log files."
  exit
fi

# Get list of killed PIDs, slow PIDs, and compare them.
KILLED=`grep $SEARCHDATE.\*SIGKILL "$PHP_FPM_ERROR_LOG" | awk '{print $7}' | sort`
SLOW=`grep $SEARCHDATE.\*pool\ www "$PHP_SLOW_LOG" | awk '{print $6}' | sort`
SLOWKILLED=`comm -1 -2 <(echo "$KILLED") <(echo "$SLOW")`

# Exit if there are no killed PIDs, otherwise it will spit out the entire slow log.
if [ -z "$SLOWKILLED" ]
then
  echo "No matches."
  exit
fi

# Iterate throught the matching PIDs, output the corresponding line from the error log with the corresponding block from the slow log.
while IFS= read -r line; do
  grep $SEARCHDATE.\*child\ $line\ .\*SIGKILL "$PHP_FPM_ERROR_LOG"
  sed -n "/$SEARCHDATE.*pid $line/,/^$/p" "$PHP_SLOW_LOG"
  #sed -n "/`date +"%d-%b-%Y"`.*pid $line/,/^$/p" "$PHP_SLOW_LOG"
done <<EOF
$SLOWKILLED
EOF

echo 
echo `comm -1 -2 <(echo "$KILLED") <(echo "$SLOW") | wc -l` matches found.
echo `diff -u <(echo "$KILLED") <(echo "$SLOW") | grep '^-[^-]' | wc -l` killed processes did not match PIDs found in the php-slow logs.

