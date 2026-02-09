#!/bin/bash

echo "=== CLIENTES DHCP CONECTADOS (LINUX) ==="
echo


if ! command -v dhcp-lease-list >/dev/null 2>&1; then
    echo "Instalando herramientas DHCP..."
    sudo apt update -y >/dev/null 2>&1
    sudo apt install isc-dhcp-server -y >/dev/null 2>&1
fi


sudo dhcp-lease-list --lease /var/lib/dhcp/dhcpd.leases
