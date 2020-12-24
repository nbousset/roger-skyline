#!/bin/bash

# This script requires iptables-persistent and ipset packages to be installed

WORKDIR='/root/roger-skyline/firewall'

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
ipset flush
ipset destroy
ipset create blacklist hash:ip timeout 60

iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 10000

#-------------------
# INPUT CHAIN

# loopback -> ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# not in blacklist -> SRCFILTER
iptables -A INPUT -m set ! --match-set blacklist src -j SRCFILTER
# DROP the rest (default policy)
# tcp -> REJECT flags=RST (to prevent port scanning)
iptables -A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
iptables -A INPUT -j REJECT --reject-with icmp-proto-unreachable

#-------------------
# SRCFILTER CHAIN

# ESTABLISHED,RELATED -> ACCEPT
iptables -A SRCFILTER -m state --state ESTABLISHED,RELATED -j ACCEPT
# below the strict limit of 3/sec/IP -> TCPFILTER
iptables -A SRCFILTER -m hashlimit --hashlimit-name srcfilter --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-upto 2/s --hashlimit-burst 2 -j TCPFILTER
# above this limit -> SET in blacklist (SET is a non-terminating target, meaning the following rules will be applied),
iptables -A SRCFILTER -j SET --add-set blacklist src
# LOG in /var/log/kern.log (non-terminating target),
iptables -A SRCFILTER -j LOG --log-prefix '/!\ SUSPECT IP: '

iptables -A SRCFILTER -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A SRCFILTER -p tcp -j REJECT --reject-with tcp-reset
iptables -A SRCFILTER -j REJECT --reject-with icmp-proto-unreachable
# DROP the rest
iptables -A SRCFILTER -j DROP

#-------------------
# TCPFILTER CHAIN

# protocol=tcp, dports=http/https/ssh, state=NEW, flags=SYN, limit-burst=50 -> ACCEPT
iptables -A TCPFILTER -p tcp -m multiport --dports 10000,443,22222 -m state --state NEW --tcp-flags ALL SYN -m limit --limit 5/s --limit-burst 50 -j ACCEPT

iptables -A SRCFILTER -p udp -j REJECT --reject-with icmp-port-unreachable
iptables -A SRCFILTER -p tcp -j REJECT --reject-with tcp-reset
iptables -A SRCFILTER -j REJECT --reject-with icmp-proto-unreachable

# everything else -> DROP
iptables -A TCPFILTER -j DROP

# Save iptables rules. Netfilter-persistent will load them at boot.
netfilter-persistent save
# Save ipset set in /etc/iptables.sets.v4
ipset save -file /etc/iptables.sets.v4
# Use our own service to load ipset sets at boot.
cp $WORKDIR/ipset-persistent/ipset-persistent.service /etc/systemd/system/
# The 2 scripts used by our service to save/load sets
cp $WORKDIR/ipset-persistent/ipset-restore.sh $WORKDIR/ipset-persistent/ipset-save.sh /usr/local/sbin/
# reload services
systemctl daemon-reload && systemctl enable ipset-persistent.service
systemctl start ipset-persistent.service && systemctl start netfilter-persistent.service
