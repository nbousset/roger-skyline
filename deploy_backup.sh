#!/bin/bash

OLDPATH="$PATH"
export PATH="/usr/sbin:$PATH"

# This script must be run as root and assumes that it is running on Debian 10.
# It doesn't handle errors and may have an undefined behaviour if a command fails or if an
# wrong parameter is provided.

#-------------------------------------------------------------------------------------------
# usage

usage() {
	echo "usage: $(basename $0) [NETWORK INTERFACE] [IP ADDRESS] [NETMASK] [GATEWAY] [options]..."
	exit 1
}

options() {
	echo "options:
	-y: force yes for packages installation
	-c: force confirmation between installation steps"
	exit 1
}

#-------------------------------------------------------------------------------------------
# parsing of options and parameters

if [ $# -lt 4 ]; then usage; fi
# could use regex to check IP/MASK/GATE format
# could check that network interface is valid (i.e. in /etc/network/interfaces)

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
gateway $GATEWAY" > "/etc/network/interfaces.d/$NETWINT"
systemctl restart networking

#-------------------------------------------------------------------------------------------
# update and install packages

$PACKMAN $PACKARG update
$PACKMAN $PACKARG upgrade

confirm "The following packages will be installed:
* vim
* sudo
* ssh
* ipset
* iptables-persistent
* sendmail
* nginx
* mariadb-server
* php-mysqli
* php-fpm"

$PACKMAN $PACKARG install vim
$PACKMAN $PACKARG install sudo
$PACKMAN $PACKARG install ssh
$PACKMAN $PACKARG install ipset
$PACKMAN $PACKARG install iptables-persistent
$PACKMAN $PACKARG install sendmail
$PACKMAN $PACKARG install nginx
$PACKMAN $PACKARG install mariadb-server
$PACKMAN $PACKARG install php-mysqli
$PACKMAN $PACKARG install php-fpm # required for nginx/php (FastCGI Process Manager)
#$PACKMAN $PACKARG install phpmyadmin # eventually

#-------------------------------------------------------------------------------------------
# add user to sudo group

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

confirm "The firewall will be configured to only accept local communication and SSH/HTTP/HTTPS incoming connections.
It will provide a basic protection against DoS and port scanning."

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

# use ipset module to create a blacklist for suspect IPs. IPs are removed from the blacklist after 60sec
ipset create blacklist hash:ip timeout 60

# INPUT CHAIN
# loopback -> ACCEPT
iptables -A INPUT -i lo -j ACCEPT
# blacklist -> DROP
iptables -A INPUT -m set --match-set blacklist src -j DROP
# ESTABLISHED,RELATED limit=100/s -> ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# NEW protocol=tcp/ports=http,https,ssh/flags=SYN limit=5/s -> IPTRACK
iptables -A INPUT -p tcp -m multiport --dports 80,443,22222 -m state --state NEW --tcp-flags ALL SYN -m limit --limit 5/s --limit-burst 50 -j IPTRACK
# tcp -> REJECT flags=RST (to prevent port scanning)
iptables -A INPUT -p tcp -j REJECT --reject-with tcp-reset
# default policy DROP

# IPTRACK CHAIN
# limit=3/s/IP -> ACCEPT All incoming connections are stored in a hashtable for 2 sec. If an address IP sends more than 3 NEW per second, it is blacklisted for 60 sec and the IP is logged
iptables -A IPTRACK -m hashlimit --hashlimit-name iptrack --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-upto 3/s --hashlimit-burst 3 --hashlimit-htable-expire 2000 -j ACCEPT
# blacklist IP
iptables -A IPTRACK -j SET --add-set blacklist src
# LOG in /var/log/kern.log
iptables -A IPTRACK -j LOG --log-prefix '/!\ SUSPECT IP: '
# tcp -> REJECT flags=RST (to prevent port scanning)
iptables -A IPTRACK -p tcp -j REJECT --reject-with tcp-reset
# DROP
iptables -A IPTRACK -j DROP

# save the rules to make them persistent
iptables-save > /etc/iptables/rules.v4
# save the ipset blacklist
#ipset save > /etc/iptables/ipset.v4

# create a service to automatically save and restore ipset sets at shutdown/boot
echo '[Unit]
Description=ipset persistent configuration
Before=netfilter-persistent.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/ipset-restore.sh
ExecStop=/usr/local/sbin/ipset-save.sh

[Install]
RequiredBy=netfilter-persistent.service' \
> /etc/systemd/system/ipset-persistent.service && chmod +x /etc/systemd/system/ipset-persistent.service

# create the 2 scripts used by the service
echo '#!/bin/sh
/sbin/ipset restore < /etc/iptables/sets.v4 || /sbin/ipset create blacklist hash:ip timeout 60; exit 0' \
> /usr/local/sbin/ipset-restore.sh && chmod +x /usr/local/sbin/ipset-restore.sh
echo '#!/bin/sh
/sbin/ipset save > /etc/iptables/sets.v4; exit 0' \
> /usr/local/sbin/ipset-save.sh && chmod +x /usr/local/sbin/ipset-save.sh

# reload services and enable ours
systemctl daemon-reload
systemctl enable ipset-persistent.service
systemctl start ipset-persistent.service

#-------------------------------------------------------------------------------------------
# stop some useless services

confirm "The following services will be disabled:
* keyboard-setup
* console-setup"

systemctl stop keyboard-setup
systemctl disable keyboard-setup
systemctl stop console-setup
systemctl disable console-setup

#-------------------------------------------------------------------------------------------
# automate updates and watch /etc/crontab

confirm "A new crontab for root will be setup:
Packages will be automatically updated once a week at 4:00 AM."

# create update_script
echo "#!/bin/sh
$PACKMAN --yes update && $PACKMAN --yes upgrade" \
> /root/update_script.sh && chmod +x /root/update_script.sh
# add crontab
echo '0 4 * * 1	/root/update_script.sh >>/var/log/update_script.log 2>&1
@reboot		/root/update_script.sh >>/var/log/update_script.log 2>&1' > /root/crontab

# create watch_cron script
echo '#!/bin/sh
if test -n "$(find /etc/crontab -mtime -1 2>/dev/null)"; then
	echo "/etc/crontab has been modified in the last 24 hours:\n\t$(ls -la /etc/crontab)" | sendmail root@localhost
fi' > /root/watch_cron.sh && chmod +x /root/watch_cron.sh
# add crontab
echo '0 0 * * *	/root/watch_cron.sh' >> /root/crontab

crontab -u root /root/crontab

#-------------------------------------------------------------------------------------------
# configure nginx and setup website

confirm "Nginx will be configured to host a website in /var/www/roger-skyline/."

echo 'server {
	listen 80;
	listen [::]:80;

	root /var/www/roger-skyline;
	index index.php;

	location / {
		try_files $uri $uri/ =404;
	}

	location ~ \.php$ {
		include snippets/fastcgi-php.conf;
		# With php-fpm (or other unix sockets):
		fastcgi_pass unix:/run/php/php7.3-fpm.sock;
	}
}' > /etc/nginx/sites-available/roger-skyline

ln -s /etc/nginx/sites-available/roger-skyline /etc/nginx/sites-enabled/roger-skyline
rm /etc/nginx/sites-enabled/default
mkdir /var/www/roger-skyline && cp website/* /var/www/roger-skyline/
systemctl restart nginx

PATH="$OLDPATH"
echo "Done."
exit 0
