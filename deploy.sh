#!/bin/bash

OLDPATH="$PATH"
export PATH="/usr/sbin:$PATH"
WORKDIR='/root/roger-skyline'

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

$WORKDIR/firewall/firewall.sh

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

cp $WORKDIR/crontab/update_script.sh /usr/local/sbin/
cp $WORKDIR/crontab/watch_cron.sh /usr/local/sbin/
crontab -u root $WORKDIR/crontab/root

#-------------------------------------------------------------------------------------------
# configure nginx and setup website

confirm "Nginx will be configured to host a website."

# the ssl cert and key
cp $WORKDIR/website/roger-skyline.crt /etc/ssl/certs/
cp $WORKDIR/website/roger-skyline.key /etc/ssl/private/
# the ssl configuration file
cp $WORKDIR/website/roger-skyline-ssl.conf /etc/nginx/snippets/
# the server configuration file
cp $WORKDIR/website/roger-skyline /etc/nginx/sites-available/
# the folder containing the srcs
mkdir /var/www/roger-skyline
cp $WORKDIR/website/src/* /var/www/roger-skyline/
# the symlink to enable the server
ln -s /etc/nginx/sites-available/roger-skyline /etc/nginx/sites-enabled/roger-skyline
# disable the default site
rm /etc/nginx/sites-enabled/default
# restart nginx
systemctl restart nginx

export PATH="$OLDPATH"
echo "Done."
exit 0
