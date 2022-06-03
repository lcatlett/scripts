#!/bin/bash

# This script outputs the sections of the php-slow log that match PIDs of php-fpm processes that were killed. The goal is to help identify slow php processes that may be causing 50x errors.
# The script only looks for matches on today's date to limit the output and hopefully prevent mismatching on reused PIDs.
# Either run the script from a directory that contains the php-fpm-error.log and php-slow.log files or change the first two variables below to point to the location of those files.

PHP_FPM_ERROR_LOG=php-fpm-error.log
PHP_SLOW_LOG=php-slow.log
TODAY=`date +"%d-%b-%Y"`

if [[ ! -f $PHP_FPM_ERROR_LOG ]] && [[ ! -f PHP_SLOW_LOG ]]
then
  echo "No php-fpm error logs or php-slow logs found."
  echo "Check that you are running the script from the correct location or modify the PHP_FPM_ERROR_LOG and PHP_SLOW_LOG variables to point to the log files."
  exit
fi

KILLED=`grep $TODAY.\*SIGKILL $PHP_FPM_ERROR_LOG | awk '{print $7}' | sort`
SLOW=`grep $TODAY.\*pool\ www $PHP_SLOW_LOG | awk '{print $6}' | sort`
SLOWKILLED=`comm -1 -2 <(echo "$KILLED") <(echo "$SLOW")`

if [ -z "$SLOWKILLED" ]
then
  echo "No matches."
  exit
fi

while IFS= read -r line; do
  grep $TODAY.\*child\ $line\ .\*SIGKILL $PHP_FPM_ERROR_LOG
  sed -n "/`date +"%d-%b-%Y"`.*pid $line/,/^$/p" $PHP_SLOW_LOG
done <<EOF
$SLOWKILLED
EOF

echo 
echo `comm -1 -2 <(echo "$KILLED") <(echo "$SLOW") | wc -l` matches found.
echo `diff -u <(echo "$KILLED") <(echo "$SLOW") | grep '^-[^-]' | wc -l` killed processes did not match PIDs found in the php-slow logs.

