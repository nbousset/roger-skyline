# reset iptables
iptables -F
iptables -P INPUT ACCCEPT
iptables -P FORWARD ACCEPT
rm /etc/iptables/rules.v4
systemctl stop netfilter-persistent
# reset ipset
ipset flush
ipset destroy
rm /etc/iptables/sets.v4
systemctl stop ipset-persistent
rm /etc/systemd/system/ipset-persistent.service
rm /etc/systemd/system/netfilter-persistent.service.requires/ipset-persistent.service
rm /usr/local/sbin/ipset-restore.sh
rm /usr/local/sbin/ipset-save.sh
# reset crons
rm /usr/local/sbin/update_script.sh
rm /usr/local/sbin/watch_cron.sh
crontab -u root -r
# reset site
rm -r /var/www/roger-skyline
rm /etc/nginx/sites-available/roger-skyline
rm /etc/nginx/sites-enabled/roger-skyline
