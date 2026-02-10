#!/bin/bash

# ==========================================
# DHCP SERVER LINUX - Menu Integrado
# ==========================================

# ==============================
# Funciones de validacion
# ==============================
function validar_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a oct <<< "$ip"
        for o in "${oct[@]}"; do
            if (( o < 0 || o > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

function en_red() {
    local ip=$1
    [[ $ip == 192.168.100.* ]]
}

function es_broadcast_o_red() {
    local ip=$1
    IFS='.' read -r -a oct <<< "$ip"
    [[ ${oct[3]} -eq 0 || ${oct[3]} -eq 255 ]]
}

function ip_a_num() {
    local ip=$1
    IFS='.' read -r -a oct <<< "$ip"
    echo $(( (${oct[0]} << 24) + (${oct[1]} << 16) + (${oct[2]} << 8) + ${oct[3]} ))
}

# ==============================
# Configuracion DHCP
# ==============================
function Configurar_DHCP() {

    echo
    echo "=============================="
    echo "   [SECCION 1] Verificando DHCP"
    echo "=============================="

    if ! dpkg -l | grep -q isc-dhcp-server; then
        echo "[+] Instalando DHCP Server..."
        sudo apt update -y >/dev/null 2>&1
        sudo apt install isc-dhcp-server -y >/dev/null 2>&1
        echo "[+] DHCP Server instalado correctamente."
    else
        echo "[-] DHCP Server ya está instalado."
    fi

    echo
    echo "=============================="
    echo "   [SECCION 2] Configuracion IP Fija"
    echo "=============================="

    echo "Interfaces disponibles:"
    ip -o link show | awk -F': ' '{print $2}'

    read -p "Nombre de la interfaz de red interna (ej: enp0s8): " IFACE

    read -p "IP del servidor DHCP (ej: 192.168.100.1): " IP_SERVER
    while ! validar_ip $IP_SERVER || ! en_red $IP_SERVER; do
        echo "Error: IP no valida o fuera de la red interna."
        read -p "Ingresa IP valida: " IP_SERVER
    done

    read -p "Prefijo de red (ej: 24): " PREFIX
    while ! [[ $PREFIX =~ ^[0-9]+$ ]] || (( PREFIX < 8 || PREFIX > 32 )); do
        echo "Error: Prefijo invalido (8-32)"
        read -p "Ingresa prefijo valido: " PREFIX
    done

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

    echo
    echo "=============================="
    echo "   [SECCION 3] Configuración del Scope DHCP"
    echo "=============================="

    read -p "Nombre del Scope: " SCOPE_NAME

    MIN_IP="192.168.100.50"
    MAX_IP="192.168.100.150"

    # IP Inicial
    while true; do
        read -p "IP inicial del rango (>= $MIN_IP): " START_IP
        if ! validar_ip $START_IP; then
            echo "Error: IP invalida"
        elif ! en_red $START_IP; then
            echo "Error: IP fuera de la red interna"
        elif (( $(ip_a_num $START_IP) < $(ip_a_num $MIN_IP) )); then
            echo "Error: IP menor que $MIN_IP"
        elif es_broadcast_o_red $START_IP; then
            echo "Error: IP no puede ser .0 o .255"
        else
            break
        fi
    done

    # IP Final
    while true; do
        read -p "IP final del rango (<= $MAX_IP): " END_IP
        if ! validar_ip $END_IP; then
            echo "Error: IP invalida"
        elif ! en_red $END_IP; then
            echo "Error: IP fuera de la red interna"
        elif (( $(ip_a_num $END_IP) > $(ip_a_num $MAX_IP) )); then
            echo "Error: IP mayor que $MAX_IP"
        elif (( $(ip_a_num $END_IP) <= $(ip_a_num $START_IP) )); then
            echo "Error: IP final debe ser mayor que la inicial"
        elif es_broadcast_o_red $END_IP; then
            echo "Error: IP no puede ser .0 o .255"
        else
            break
        fi
    done

    # Gateway
    while true; do
        read -p "Gateway: " GATEWAY
        if ! validar_ip $GATEWAY; then
            echo "Error: IP invalida"
        elif ! en_red $GATEWAY; then
            echo "Error: Gateway fuera de la red interna"
        elif [[ "$GATEWAY" == "$IP_SERVER" ]]; then
            echo "Error: Gateway no puede ser la misma IP que el servidor"
        else
            break
        fi
    done

    # DNS
    while true; do
        read -p "DNS: " DNS
        if ! validar_ip $DNS; then
            echo "Error: IP inválida"
        elif [[ "$DNS" == "0.0.0.0" ]]; then
            echo "Error: DNS no puede ser 0.0.0.0"
        else
            break
        fi
    done

    # Tiempo de concesión
    while true; do
        read -p "Tiempo de concesion (en minutos): " LEASE_MIN
        if ! [[ $LEASE_MIN =~ ^[0-9]+$ ]] || (( LEASE_MIN <= 0 )); then
            echo "Error: Ingresa un numero valido"
        else
            break
        fi
    done

    # Crear dhcpd.conf
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
    echo "DHCP configurado correctamente."
    read -p "Presiona Enter para regresar al menu..."
}

# ==============================
# Monitoreo de clientes
# ==============================
function Monitorear_Clientes() {
    echo
    echo "=== CLIENTES DHCP CONECTADOS (LINUX) ==="
    echo

    if ! command -v dhcp-lease-list >/dev/null 2>&1; then
        echo "[+] Instalando herramientas de monitoreo DHCP..."
        sudo apt update -y >/dev/null 2>&1
        sudo apt install isc-dhcp-server -y >/dev/null 2>&1
    fi

    sudo dhcp-lease-list --lease /var/lib/dhcp/dhcpd.leases
    echo
    read -p "Presiona Enter para regresar al menu..."
}

# ==============================
# Estado del servicio DHCP
# ==============================
function Estado_Servicio() {
    echo
    echo "=== ESTADO DEL SERVICIO DHCP ==="
    sudo systemctl status isc-dhcp-server --no-pager
    echo
    read -p "Presiona Enter para regresar al menu..."
}

# ==============================
# Menu principal
# ==============================
while true; do
    clear
    echo "======================================"
    echo "       MENU DHCP SERVER LINUX"
    echo "======================================"
    echo "1) Configurar DHCP Server"
    echo "2) Monitorear clientes conectados"
    echo "3) Consultar estado del servidor DHCP"
    echo "4) Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) Configurar_DHCP ;;
        2) Monitorear_Clientes ;;
        3) Estado_Servicio ;;
        4) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida"; sleep 1 ;;
    esac
done
