#!/bin/bash

WORKDIR='/root/roger-skyline'

# Flush
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
# Default policies in built-in chains
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
# Add user-defined chain for IP tracking and filtering (DoS prevention)
iptables -N SRCFILTER
# Add user-defined chain for protocol and destination filtering
iptables -N TCPFILTER
# use ipset module to create a blacklist for suspect IPs. IPs are blacklisted for 60sec
ipset create blacklist hash:ip timeout 60

#-------------------
# INPUT CHAIN

# loopback -> ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# not in blacklist -> SRCFILTER
iptables -A INPUT -m set --match-set blacklist src --return-nomatch -j SRCFILTER
# DROP the rest (default policy)

#-------------------
# SRCFILTER CHAIN

# ESTABLISHED,RELATED -> ACCEPT
iptables -A SRCFILTER -m state --state ESTABLISHED,RELATED -j ACCEPT
# below the strict limit of 3/sec/IP -> TCPFILTER
iptables -A SRCFILTER -m hashlimit --hashlimit-name srcfilter --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-upto 3/s --hashlimit-burst 3 --hashlimit-htable-expire 2000 -j TCPFILTER
# above this limit -> SET in blacklist (SET is a non-terminating target, meaning the following rules will be applied),
iptables -A SRCFILTER -j SET --add-set blacklist src
# LOG in /var/log/kern.log (non-terminating target),
iptables -A SRCFILTER -j LOG --log-prefix '/!\ SUSPECT IP: '
# DROP the rest
iptables -A SRCFILTER -j DROP

#-------------------
# TCPFILTER CHAIN

# protocol=tcp, dports=http/https/ssh, state=NEW, flags=SYN, limit-burst=50 -> ACCEPT
iptables -A TCPFILTER -p tcp -m multiport --dports 80,443,22222 -m state --state NEW --tcp-flags ALL SYN -m limit --limit 5/s --limit-burst 50 -j ACCEPT
# everything else -> DROP
iptables -A TCPFILTER -j DROP

# Netfilter-persistent.service will automatically save/load the iptables rules at shutdown/boot.
# There is no such service for ipset, so we must use our own service to do this. This service is
# a dependency for netfilter-persistent, as iptables rules reference ipset sets.
cp $WORKDIR/ipset-persistent/ipset-persistent.service /etc/systemd/system/
# Those are 2 scripts used by the service
cp $WORKDIR/ipset-persistent/ipset-restore.sh $WORKDIR/ipset-persistent/ipset-save.sh /usr/local/sbin/
# reload services and start ours
systemctl daemon-reload && systemctl enable ipset-persistent.service
systemctl start ipset-persistent.service
systemctl start netfilter-persistent.service
