#!/bin/bash

OLDPATH="$PATH"
export PATH="/usr/sbin:$PATH"

# This script must be run as root and assumes that it is running on Debian.
# It doesn't handle errors and may have an undefined behaviour if a command fails or if an
# wrong parameter is provided.

#-------------------------------------------------------------------------------------------
# usage

usage()
{
	echo "usage: $(basename $0) [NETWORK INTERFACE] [IP ADDRESS] [NETMASK] [GATEWAY] [options]..."
	exit 1
}

options()
{
	echo "options:
	-y: force yes for packages installation
	-c: force confirmation between installation steps"
	exit 1
}

#-------------------------------------------------------------------------------------------
# parsing of options and parameters

if [ $# -lt 4 ]; then usage; fi
# could use regex to check IP/MASK/GATE format
# could check that network interface is valid (in /etc/network/interfaces)

NETWINT=$1
ADDRESS=$2
NETMASK=$3
GATEWAY=$4
shift 4

PACKMAN="apt-get"
PACKARG=""
CONFIRM="true"
while getopts ":yc" opt; do
	case $opt in
		y )
			PACKARG="--yes"
			;;
		c )
			CONFIRM="false"
			;;
		\? ) 
			echo "$(basename $0): invalid option: -$OPTARG" && options
			;;
	esac
done


#-------------------------------------------------------------------------------------------
# tools

confirm() { $CONFIRM && echo "$1" && read -p "Press enter to continue"; }

#-------------------------------------------------------------------------------------------
# setup static address

confirm "The network will be restarted with the new configuration."

sed -i "s/iface $NETWINT inet dhcp/auto $NETWINT/" /etc/network/interfaces
echo "iface $NETWINT inet static
address $ADDRESS
netmask $NETMASK
gateway $GATEWAY" >"/etc/network/interfaces.d/$NETWINT"
systemctl restart networking

#-------------------------------------------------------------------------------------------
# update and install packages

$PACKMAN $PACKARG update
$PACKMAN $PACKARG upgrade

confirm "The following packages will be installed:
* sudo
* ssh
* iptables-persistent
* sendmail"

$PACKMAN $PACKARG install sudo
$PACKMAN $PACKARG install ssh
$PACKMAN $PACKARG install iptables-persistent
$PACKMAN $PACKARG install sendmail

#-------------------------------------------------------------------------------------------
# add user to sudo group

# could ask for users to be added
usermod -aG sudo user

#-------------------------------------------------------------------------------------------
# setup ssh

confirm "SSH will now be configured to only accept public key authentication on port 22222.
If you want to add public keys via SSH, you should add them before continuing."

sed -i "s/^#Port.*/Port 22222/" /etc/ssh/sshd_config
sed -i "s/^#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/^#PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config
systemctl restart ssh

#-------------------------------------------------------------------------------------------
# setup firewall

confirm "The firewall will be configured persistently to accept only SSH/HTTP/HTTPS incoming connections and provide a basic protection against DoS and port scanning."

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

# Add user-defined chain for IP tracking (DoS prevention)
iptables -N IPTRACK

# INPUT CHAIN
# loopback -> ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# ESTABLISHED,RELATED limit=100/s -> ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# NEW protocol=tcp/ports=http,https,ssh/flags=SYN limit=5/s -> IPTRACK
iptables -A INPUT -p tcp -m multiport --dports 80,443,22222 -m state --state NEW --tcp-flags ALL SYN -m limit --limit 5/s --limit-burst 50 -j IPTRACK
# tcp -> REJECT flags=RST (to prevent port scanning)
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
# default policy DROP

# IPTRACK CHAIN
# limit=5/s/IP -> ACCEPT
iptables -A IPTRACK -m hashlimit --hashlimit-name iptrack --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-upto 5/s --hashlimit-burst 5 -j ACCEPT
# LOG in /var/log/kern.log
iptables -A IPTRACK -j LOG --log-prefix '/!\ SUSPECT IP: '
# tcp -> REJECT flags=RST (to prevent port scanning)
iptables -A IPTRACK -p tcp -j REJECT --reject-with tcp-reset
# DROP
iptables -A IPTRACK -j DROP

# save the rules to make them persistent
iptables-save >/etc/iptables/rules.v4

#-------------------------------------------------------------------------------------------
# automate updates and watch /etc/crontab

confirm "A new crontab for root will be setup:
Packages will be automatically updated once a week at 4:00 AM."

echo "$PACKMAN --yes update && $PACKMAN --yes upgrade" > /root/update_script.sh && chmod +x /root/update_script.sh
echo '0 4 * * 1	/root/update_script.sh >>/var/log/update_script.log 2>&1
@reboot		/root/update_script.sh >>/var/log/update_script.log 2>&1' >/root/crontab

echo 'if test -n "$(find /etc/crontab -mtime -1 2>/dev/null)"; then
	echo "/etc/crontab has been modified in the last 24 hours:\n\t$(ls -la /etc/crontab)" | sendmail root@localhost
fi' >/root/watch_cron.sh && chmod +x /root/watch_cron.sh
echo '0 0 * * *	/root/watch_cron.sh' >>/root/crontab

crontab -u root /root/crontab

PATH="$OLDPATH"
echo "Done."
exit 0
