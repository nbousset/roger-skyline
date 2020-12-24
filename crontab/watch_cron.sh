#!/bin/sh

if test -n "$(find /etc/crontab -mtime -1 2>/dev/null)"; then
	echo "/etc/crontab has been modified in the last 24 hours:\n\t$(ls -la /etc/crontab)" | sendmail root@localhost
fi
