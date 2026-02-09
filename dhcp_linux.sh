echo "DHCP SERVER LINUX"
if ! dpkg -l | grep -q isc-dhcp-server; then
    echo "[+] Instalando DHCP Server..."
    sudo apt update -y >/dev/null 2>&1
    sudo apt install isc-dhcp-server -y >/dev/null 2>&1
else
    echo "[-] DHCP Server ya está instalado."
fi

echo "Interfaces disponibles:"
ip -o link show | awk -F': ' '{print $2}'

IP_SERVER="192.168.100.20"
PREFIX="24"

NETPLAN_FILE="/etc/netplan/00-dhcp-interno.yaml"

sudo tee $NETPLAN_FILE >/dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses: [$IP_SERVER/$PREFIX]
EOF

sudo netplan apply

sudo sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$IFACE\"/" /etc/default/isc-dhcp-server
read -p "Nombre del Scope: " SCOPE_NAME
read -p "IP inicial del rango: " START_IP
read -p "IP final del rango: " END_IP
read -p "Gateway: " GATEWAY
read -p "DNS: " DNS
read -p "Tiempo de concesión (en minutos): " LEASE_MIN

sudo tee /etc/dhcp/dhcpd.conf >/dev/null <<EOF
default-lease-time $((LEASE_MIN*60));
max-lease-time $((LEASE_MIN*120));

subnet 192.168.100.0 netmask 255.255.255.0 {
  range $START_IP $END_IP;
  option routers $GATEWAY;
  option domain-name-servers $DNS;
}
EOF

sudo systemctl restart isc-dhcp-server

echo "DHCP configurado"
