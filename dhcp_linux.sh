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
# Estado de instalación DHCP
# ==============================
function Estado_Instalacion() {
    echo
    echo "=== ESTADO DE INSTALACION DHCP ==="
    if dpkg -l | grep -q isc-dhcp-server; then
        echo "[+] El paquete isc-dhcp-server está instalado."
    else
        echo "[-] El paquete isc-dhcp-server NO está instalado."
    fi
    echo
    read -p "Presiona Enter para regresar al menu..."
}

# ==============================
# Instalación silenciosa DHCP
# ==============================
function Instalar_Silencioso() {
    echo
    echo "=== INSTALACION SILENCIOSA DHCP ==="
    if dpkg -l | grep -q isc-dhcp-server; then
        echo "[+] DHCP Server ya está instalado."
    else
        echo "[+] Instalando isc-dhcp-server en modo silencioso..."
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server >/dev/null 2>&1
        echo "[+] Instalación completada."
    fi
    echo
    read -p "Presiona Enter para regresar al menu..."
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
    while ! validar_ip $IP_SERVER; do
        echo "Error: IP no valida."
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

    # IP Inicial
    while true; do
        read -p "IP inicial del rango DHCP: " START_IP
        if ! validar_ip $START_IP; then
            echo "Error: IP invalida"
        elif es_broadcast_o_red $START_IP; then
            echo "Error: IP no puede ser .0 o .255"
        else
            break
        fi
    done

    # IP Final
    while true; do
        read -p "IP final del rango DHCP: " END_IP
        if ! validar_ip $END_IP; then
            echo "Error: IP invalida"
        elif (( $(ip_a_num $END_IP) <= $(ip_a_num $START_IP) )); then
            echo "Error: IP final debe ser mayor que la inicial"
        elif es_broadcast_o_red $END_IP; then
            echo "Error: IP no puede ser .0 o .255"
        else
            break
        fi
    done

    # Gateway (opcional)
    read -p "Gateway (opcional, Enter para omitir): " GW
    if [[ -n "$GW" ]]; then
        while ! validar_ip $GW; do
            echo "Error: IP invalida"
            read -p "Ingresa IP Gateway valida o Enter para omitir: " GW
            [[ -z "$GW" ]] && break
        done
    fi

    # DNS (opcional)
    read -p "DNS (opcional, Enter para omitir): " DNS
    if [[ -n "$DNS" ]]; then
        while ! validar_ip $DNS; do
            echo "Error: IP invalida"
            read -p "Ingresa IP DNS valida o Enter para omitir: " DNS
            [[ -z "$DNS" ]] && break
        done
    fi

    # Tiempo de concesion
    read -p "Tiempo de concesion (en minutos): " LEASE
    while ! [[ $LEASE =~ ^[0-9]+$ ]] || (( LEASE <= 0 )); do
        echo "Error: Ingresa un numero valido"
        read -p "Tiempo de concesion (en minutos): " LEASE
    done

    # Crear dhcpd.conf con el nuevo formato
    NET="${START_IP%.*}"
    RANGO_INI="$START_IP"
    IP_FIN="$END_IP"

    cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf > /dev/null
subnet $NET.0 netmask 255.255.255.0 {
  range $RANGO_INI $IP_FIN;
  option subnet-mask 255.255.255.0;
  ${GW:+option routers $GW;}
  ${DNS:+option domain-name-servers $DNS;}
  default-lease-time $((LEASE*60));
  max-lease-time $((LEASE*60));
}
EOF

    echo "Configuración completada."
    read -p "Presiona Enter para regresar al menu..."
}


# ==============================
# Iniciar / Reiniciar DHCP
# ==============================
function Iniciar_DHCP() {
    echo
    echo "=== INICIANDO / REINICIANDO SERVICIO DHCP ==="
    sudo systemctl enable isc-dhcp-server
    sudo systemctl restart isc-dhcp-server
    sudo systemctl status isc-dhcp-server --no-pager
    echo
    read -p "Presiona Enter para regresar al menu..."
}

# ==============================
# Monitoreo de clientes
# ==============================
function Monitorear_Clientes() {
    echo
    echo "=== CLIENTES DHCP CONECTADOS (LINUX) ==="
    echo

    if [[ ! -f /var/lib/dhcp/dhcpd.leases ]]; then
        echo "No hay clientes conectados o archivo de leases no existe."
    else
        sudo awk '/lease/ {ip=$2} /hardware ethernet/ {mac=$3} /client-hostname/ {host=$2} /ends/ {print "IP: " ip ", MAC: " mac ", Host: " host}' /var/lib/dhcp/dhcpd.leases
    fi

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
    echo "1) Verificar instalación del DHCP Server"
    echo "2) Instalar DHCP Server (silencioso)"
    echo "3) Configurar DHCP Server"
    echo "4) Iniciar / Reiniciar DHCP Server"
    echo "5) Monitorear clientes conectados"
    echo "6) Consultar estado del servicio DHCP"
    echo "7) Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1) Estado_Instalacion ;;
        2) Instalar_Silencioso ;;
        3) Configurar_DHCP ;;
        4) Iniciar_DHCP ;;
        5) Monitorear_Clientes ;;
        6) Estado_Servicio ;;
        7) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida"; sleep 1 ;;
    esac
done


