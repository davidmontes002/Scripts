# ==========================================
# DHCP SERVER WINDOWS - SCRIPT COMPLETO
# ==========================================

function validar-ip {
    param([string]$ip)
    if ($ip -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $octetos = $ip.Split('.')
        foreach ($o in $octetos) { if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false } }
        return $true
    }
    return $false
}

function en-red {
    param([string]$ip)
    return $ip.StartsWith("192.168.100.")
}

function IPaNum {
    param([string]$ip)
    $p = $ip.Split('.')
    return ([int]$p[0] -shl 24) + ([int]$p[1] -shl 16) + ([int]$p[2] -shl 8) + [int]$p[3]
}

function es-broadcast-o-red {
    param([string]$ip)
    $oct = $ip.Split('.')
    return ($oct[3] -eq 0 -or $oct[3] -eq 255)
}

# ==============================
# Funcion de configuracion DHCP
# ==============================
function Configurar-DHCP {
    echo "`n[SECCION 1] Verificando DHCP Server..."
    $dhcp = Get-WindowsFeature -Name DHCP
    if (-not $dhcp.Installed) {
        echo "[+] Instalando rol DHCP..."
        Install-WindowsFeature DHCP -IncludeManagementTools
        echo "[+] DHCP instalado correctamente."
    } else { echo "[-] DHCP ya esta instalado." }

    echo "`n[SECCION 2] Configuracion IP fija del servidor..."
    $AdaptadorInterno = "Ethernet 2"
    $IPServidor = "192.168.100.10"
    $Mascara = 24

    Get-NetIPAddress -InterfaceAlias $AdaptadorInterno -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue *> $null
    New-NetIPAddress -InterfaceAlias $AdaptadorInterno -IPAddress $IPServidor -PrefixLength $Mascara -ErrorAction SilentlyContinue *> $null

    echo "`n[SECCION 3] Configuracion del rango DHCP..."
    $MIN_IP = "192.168.100.50"
    $MAX_IP = "192.168.100.150"

    $scopeName = Read-Host "Nombre del Scope"

    # IP inicial
    do {
        $startIP = Read-Host "IP inicial (>= $MIN_IP)"
        if (-not (validar-ip $startIP)) { echo "Error: IP no válida."; $startIP = $null }
        elseif (-not (en-red $startIP)) { echo "Error: IP fuera de la red interna."; $startIP = $null }
        elseif ((IPaNum $startIP) -lt (IPaNum $MIN_IP)) { echo "Error: IP menor que $MIN_IP."; $startIP = $null }
        elseif (es-broadcast-o-red $startIP) { echo "Error: IP no puede ser .0 ni .255"; $startIP = $null }
    } until ($startIP)

    # IP final
    do {
        $endIP = Read-Host "IP Final (<= $MAX_IP)"
        if (-not (validar-ip $endIP)) { echo "Error: IP no valida."; $endIP = $null }
        elseif (-not (en-red $endIP)) { echo "Error: IP fuera de la red interna."; $endIP = $null }
        elseif ((IPaNum $endIP) -gt (IPaNum $MAX_IP)) { echo "Error: IP mayor que $MAX_IP"; $endIP = $null }
        elseif ((IPaNum $endIP) -le (IPaNum $startIP)) { echo "Error: La IP final debe ser mayor que la inicial."; $endIP = $null }
        elseif (es-broadcast-o-red $endIP) { echo "Error: IP no puede ser .0 ni .255"; $endIP = $null }
    } until ($endIP)

    # Validar que IP del servidor no esté en rango DHCP
    do {
        if ((IPaNum $IPServidor) -ge (IPaNum $startIP) -and (IPaNum $IPServidor) -le (IPaNum $endIP)) {
            echo "Error: La IP del servidor ($IPServidor) no puede estar dentro del rango DHCP."
            $IPServidor = Read-Host "Ingresa otra IP para el servidor DHCP"
        }
    } until ((IPaNum $IPServidor) -lt (IPaNum $startIP) -or (IPaNum $IPServidor) -gt (IPaNum $endIP))

    # Tiempo de concesion
    do {
        $lease = Read-Host "Tiempo de Concesion (en Horas)"
        if (-not ($lease -match '^\d+$') -or $lease -le 0) { echo "Error: Ingresa un numero valido de horas."; $lease = $null }
    } until ($lease)

    # Gateway
    do {
        $gateway = Read-Host "Gateway"
        if (-not (validar-ip $gateway)) { echo "Error: IP gateway no valida"; $gateway = $null }
        elseif (-not (en-red $gateway)) { echo "Error: Gateway fuera de la red interna"; $gateway = $null }
        elseif ($gateway -eq $IPServidor) { echo "Error: Gateway no puede ser la misma IP del servidor"; $gateway = $null }
    } until ($gateway)

    # DNS
    do {
        $dns = Read-Host "DNS"
        if (-not (validar-ip $dns)) { echo "Error: IP DNS no valida"; $dns = $null }
        elseif ($dns -eq "0.0.0.0") { echo "Error: DNS no puede ser 0.0.0.0"; $dns = $null }
    } until ($dns)

    echo "`n[SECCION 4] Creando Scope DHCP..."
    if (-not (Get-DhcpServerv4Scope | Where-Object {$_.Name -eq $scopeName})) {
        Add-DhcpServerv4Scope -Name $scopeName -StartRange $startIP -EndRange $endIP -SubnetMask "255.255.255.0" -State Active
        Set-DhcpServerv4OptionValue -ScopeId $startIP -Router $gateway -DnsServer $dns
        Set-DhcpServerv4Scope -ScopeId $startIP -LeaseDuration ([TimeSpan]::FromHours($lease))
        echo "[+] Scope '$scopeName' creado y configurado."
    } else { echo "[-] Scope '$scopeName' ya existe." }

    echo "`n[SECCION 5] Iniciando servicio DHCP..."
    Start-Service -Name DHCPServer
    Set-Service -Name DHCPServer -StartupType Automatic
    echo "[+] Servicio DHCP iniciado y habilitado al inicio."
}

# ======================================
# Función de Monitoreo del DHCP
# ======================================
function Monitorear-DHCP {
    echo "`n[MONITOREO] Estado del servicio DHCP:"
    Get-Service -Name DHCPServer | Select-Object Status, StartType

    echo "`n[MONITOREO] Clientes conectados por DHCP:"
    $scopes = Get-DhcpServerv4Scope
    foreach ($scope in $scopes) {
        echo "`nScope:" $scope.Name " - " $scope.ScopeId
        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId
        if ($leases.Count -eq 0) { echo "  No hay clientes conectados." } 
        else {
            foreach ($lease in $leases) {
                echo "-----------------------------------"
                echo "IP       :" $lease.IPAddress
                echo "MAC      :" $lease.ClientId
                echo "Host     :" $lease.HostName
                echo "Expira   :" $lease.LeaseExpiryTime
            }
        }
    }
}

# ======================================
# Función de Estado en Tiempo Real
# ======================================
function Estado-Servidor {
    echo "`n[ESTADO EN TIEMPO REAL] Servicio DHCP y Scopes:"
    $service = Get-Service -Name DHCPServer
    echo "Servicio DHCPServer:"
    echo "  Estado : $($service.Status)"
    echo "  Tipo inicio : $($service.StartType)"

    $scopes = Get-DhcpServerv4Scope
    echo "`nScopes configurados: $($scopes.Count)"
    foreach ($scope in $scopes) {
        echo "  - $($scope.Name) [$($scope.ScopeId)]"
    }

    echo "`nUltimos 5 eventos DHCP (Application Log):"
    Get-WinEvent -LogName "Microsoft-Windows-DHCP-Server/Operational" -MaxEvents 5 |
        Select-Object TimeCreated, Id, LevelDisplayName, Message |
        Format-Table -AutoSize
}

# ======================================
# MENÚ PRINCIPAL
# ======================================
do {
    echo "`n============================="
    echo " DHCP SERVER - MENU PRINCIPAL"
    echo "============================="
    echo "1) Configurar DHCP Server"
    echo "2) Monitorear Clientes Conectados"
    echo "3) Consultar Estado del Servidor en Tiempo Real"
    echo "4) Salir"
    $opcion = Read-Host "Selecciona una opcion (1-4)"

    switch ($opcion) {
        "1" { Configurar-DHCP }
        "2" { Monitorear-DHCP }
        "3" { Estado-Servidor }
        "4" { echo "Saliendo..."; break }
        default { echo "Opcion no valida. Intenta de nuevo." }
    }

} until ($opcion -eq "4")

