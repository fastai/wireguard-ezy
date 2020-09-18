#!/usr/bin/env bash
set -e

echo
if ! [[ $(id -u) = 0 ]]; then
  echo "Please run 'sudo ./install-wireguard.sh'" >&2
  exit 1
fi

read -e -p "Use VPN for *all* internet traffic? [y/n] " -i n ROUTE_ALL
if [[ $ROUTE_ALL = y* ]]; then
  SUBNET=0.0.0.0/0
elif [[ $ROUTE_ALL = n* ]]; then
  SUBNET=10.42.42.0/24
else
  echo Unknown response
  exit 1
fi

read -e -p "# of clients? [Betwen 1 and 253] " -i 5 NUM
read -e -p "Server hostname/IP? " -i $(curl -s ifconfig.me) SERVER

apt-get install -qq wireguard zip
if [ `sysctl net.ipv4.ip_forward -b` == 0 ]; then
  echo "running this"
  cat "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sysctl.conf
  sysctl -w net.ipv4.ip_forward=1
fi
wg genkey | tee server.key | wg pubkey > server.pub

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.42.42.1/24
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i wg0 -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
ListenPort = 51820
PrivateKey = $(cat server.key)
EOF

systemctl start wg-quick@wg0
wg

# IP 1 is reserved for server
NUM=$(($NUM + 1))
for i in $(seq 2 $NUM); do . ./add-client.sh $i; done

ufw allow 51820/udp
systemctl enable wg-quick@wg0

if [ $SUDO_USER ]; then user=$SUDO_USER
else user=$(whoami); fi
zip -rq clients clients
chown $user clients.zip

echo 
echo Done. clients.tgz contains your client configuration files.
echo To add clients in the future run:
echo "   sudo SERVER=$SERVER SUBNET=$SUBNET ./add-client.sh NUMBER"
echo where NUMBER is the client number to create, which must be larger than $NUM

