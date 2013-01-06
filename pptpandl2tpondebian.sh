#!/bin/bash

if [ $(id -u) != "0" ]; then
    printf "Error: You must be root to run this tool!\n"
    exit 1
fi
clear
vpsip=`ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | cut -d: -f2 | awk 'NR==1 { print $1}'`
iprange="10.0.99"
echo "Please input IP-Range:"
read -p "(Default Range: 10.0.99):" iprange
if [ "$iprange" = "" ]; then
	iprange="10.0.99"
fi

mypsk="8ke"
echo "Please input PSK:"
read -p "(Default PSK: 8ke):" mypsk
if [ "$mypsk" = "" ]; then
	mypsk="8ke"
fi

get_char()
{
SAVEDSTTY=`stty -g`
stty -echo
stty cbreak
dd if=/dev/tty bs=1 count=1 2> /dev/null
stty -raw
stty echo
stty $SAVEDSTTY
}
echo ""
echo "ServerIP:"
echo "$vpsip"
echo ""
echo "Server Local IP:"
echo "$iprange.1"
echo ""
echo "Client Remote IP Range:"
echo "$iprange.2-$iprange.254"
echo ""
echo "PSK:"
echo "$mypsk"
echo ""
echo "Press any key to start..."
char=`get_char`
clear

apt-get -y update
apt-get -y upgrade
apt-get --purge remove pptpd ppp
rm -rf /etc/pptpd.conf
rm -rf /etc/ppp
apt-get install -y ppp
apt-get install -y pptpd
apt-get install -y iptables logrotate tar cpio perl
apt-get -y install libgmp3-dev bison flex libpcap-dev ppp iptables make gcc lsof vim
rm -r /dev/ppp
mknod /dev/ppp c 108 0
echo 1 > /proc/sys/net/ipv4/ip_forward 
echo "mknod /dev/ppp c 108 0" >> /etc/rc.local
echo "localip 10.10.10.1" >> /etc/pptpd.conf
echo "remoteip 10.10.10.100-200" >> /etc/pptpd.conf
echo "ms-dns 8.8.8.8" >> /etc/ppp/options.pptpd
echo "ms-dns 8.8.4.4" >> /etc/ppp/options.pptpd
echo "ms-dns 8.8.8.8" >> /etc/pptpd.conf
echo "ms-dns 8.8.4.4" >> /etc/pptpd.conf
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE
clear
mkdir /ztmp
mkdir /ztmp/l2tp
cd /ztmp/l2tp
wget -c --no-check-certificate  http://www.openswan.org/download/openswan-2.6.24.tar.gz
tar zxvf openswan-2.6.24.tar.gz
cd openswan-2.6.24
make programs install
rm -rf /etc/ipsec.conf
touch /etc/ipsec.conf
cat >>/etc/ipsec.conf<<EOF
config setup
    nat_traversal=yes
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12
    oe=off
    protostack=netkey

conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=$vpsip
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
EOF
cat >>/etc/ipsec.secrets<<EOF
$vpsip %any: PSK "$mypsk"
EOF
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g' /etc/sysctl.conf
sysctl -p
iptables --table nat --append POSTROUTING --jump MASQUERADE
for each in /proc/sys/net/ipv4/conf/*
do
echo 0 > $each/accept_redirects
echo 0 > $each/send_redirects
done
/etc/init.d/ipsec restart
ipsec verify
cd /ztmp/l2tp
wget -c --no-check-certificate http://mirror.zeddicus.com/sources/rp-l2tp-0.4.tar.gz
tar zxvf rp-l2tp-0.4.tar.gz
cd rp-l2tp-0.4
./configure
make
cp handlers/l2tp-control /usr/local/sbin/
mkdir /var/run/xl2tpd/
ln -s /usr/local/sbin/l2tp-control /var/run/xl2tpd/l2tp-control
cd /ztmp/l2tp
wget -c --no-check-certificate http://mirror.zeddicus.com/sources/xl2tpd-1.2.4.tar.gz
tar zxvf xl2tpd-1.2.4.tar.gz
cd xl2tpd-1.2.4
make install
mkdir /etc/xl2tpd
rm -rf /etc/xl2tpd/xl2tpd.conf
touch /etc/xl2tpd/xl2tpd.conf
cat >>/etc/xl2tpd/xl2tpd.conf<<EOF
[global]
ipsec saref = yes
[lns default]
ip range = $iprange.2-$iprange.254
local ip = $iprange.1
refuse chap = yes
refuse pap = yes
require authentication = yes
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF
rm -rf /etc/ppp/options.xl2tpd
touch /etc/ppp/options.xl2tpd
cat >>/etc/ppp/options.xl2tpd<<EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
EOF
cat >>/etc/ppp/chap-secrets<<EOF
test * 8ke *
EOF
touch /usr/bin/zl2tpset
echo "#/bin/bash" >>/usr/bin/zl2tpset
echo "for each in /proc/sys/net/ipv4/conf/*" >>/usr/bin/zl2tpset
echo "do" >>/usr/bin/zl2tpset
echo "echo 0 > \$each/accept_redirects" >>/usr/bin/zl2tpset
echo "echo 0 > \$each/send_redirects" >>/usr/bin/zl2tpset
echo "done" >>/usr/bin/zl2tpset
chmod +x /usr/bin/zl2tpset
iptables --table nat --append POSTROUTING --jump MASQUERADE
zl2tpset
xl2tpd
sed -i 's#!/bin/sh -e#!/bin/bash#g' /etc/rc.local
sed -i 's/exit 0/ /g' /etc/rc.local
cat >>/etc/rc.local<<EOF
iptables --table nat --append POSTROUTING --jump MASQUERADE
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE
/etc/init.d/ipsec restart
/usr/bin/zl2tpset
/usr/local/sbin/xl2tpd
EOF
clear
ipsec verify
printf "
ServerIP:$vpsip
测试用户名与密码为：test / 8ke，记录于 /etc/ppp/chap-secrets 。enjoy it.
如果重启后用不了
编辑/etc/rc.local文件
把第一行改成
#!/bin/bash
然后去掉exit 0那行就行了
"
