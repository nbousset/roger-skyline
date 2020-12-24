#!/bin/sh

/sbin/ipset restore -file /etc/iptables/sets.v4 || /sbin/ipset create blacklist hash:ip timeout 60
exit 0
