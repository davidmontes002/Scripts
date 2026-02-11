#[Seccion_1]-----------------------------------------------------------------------------------------------
function Estado-DHCP {
    Write-Host "--------------------------------" -ForegroundColor Yellow
    Write-Host "`n[ESTADO DEL SERVIDOR DHCP]" -ForegroundColor Yellow
    Write-Host "--------------------------------" -ForegroundColor Yellow

    # 1. Verificar si el rol DHCP está instalado
    $feature = Get-WindowsFeature -Name DHCP

    if (-not $feature.Installed) {
        Write-Host "El rol DHCP Server NO está instalado en este servidor." -ForegroundColor Red
        Write-Host "Usa la opcion 'Instalar DHCP' desde el menu."
        return
    }

    Write-Host "Rol DHCP Server: INSTALADO" -ForegroundColor Green

    # 2. Verificar servicio DHCP
    $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Host "El servicio DHCPServer no existe." -ForegroundColor Red
        return
    }

    Write-Host "`n[Servicio DHCPServer]"
    Write-Host "Estado       : $($service.Status)"
    Write-Host "Tipo de inicio: $($service.StartType)"

    if ($service.Status -ne "Running") {
        Write-Host "El servicio DHCP está instalado pero NO está activo." -ForegroundColor Yellow
        return
    }

    # 3. Detalles si está activo
    Write-Host "`n[Detalles del DHCP Activo]" -ForegroundColor Cyan

    $scopes = Get-DhcpServerv4Scope

    if ($scopes.Count -eq 0) {
        Write-Host "No hay scopes configurados."
    } else {
        Write-Host "Scopes configurados: $($scopes.Count)"
        foreach ($scope in $scopes) {
            Write-Host "-----------------------------------"
            Write-Host "Nombre     : $($scope.Name)"
            Write-Host "Scope ID   : $($scope.ScopeId)"
            Write-Host "Estado     : $($scope.State)"
            Write-Host "Rango      : $($scope.StartRange) - $($scope.EndRange)"
            Write-Host "Mascara    : $($scope.SubnetMask)"
        }
    }

    Write-Host "`n[Fin del estado DHCP]"
}
#----------------------------------------------------------------------------------[Fin Seccion_1]

#[Seccion_2]--------------------------------------------------------------------------------------
function Instalar-DHCP {

    Write-Host "`n[OPCION 2 - INSTALAR DHCP SERVER]" -ForegroundColor Yellow
    Write-Host "--------------------------------"

    $feature = Get-WindowsFeature -Name DHCP

    if ($feature.Installed) {
        Write-Host "DHCP Server ya esta instalado." -ForegroundColor Yellow
    } else {
        Write-Host "Instalando rol DHCP Server..."
        Install-WindowsFeature DHCP -IncludeManagementTools

        $feature = Get-WindowsFeature -Name DHCP
        if ($feature.Installed) {
            Write-Host "DHCP Server instalado correctamente." -ForegroundColor Green
        } else {
            Write-Host "Error: No se pudo instalar DHCP Server." -ForegroundColor Red
            return
        }
    }

    # Iniciar servicio si no esta activo
    $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    if ($service.Status -ne "Running") {
        Write-Host "Iniciando servicio DHCPServer..."
        Start-Service -Name DHCPServer
    }

    # Dejar inicio automatico
    Set-Service -Name DHCPServer -StartupType Automatic

    Write-Host "`nEstado del servicio DHCP:"
    Get-Service -Name DHCPServer | Select-Object Status, StartType | Format-Table -AutoSize
}
#----------------------------------------------------------------------------------[Fin Seccion_2]

#[Seccion_3]--------------------------------------------------------------------------------------
function Configurar-DHCP {

    Write-Host "`n==============================="
    Write-Host "   OPCION 3 - CONFIGURAR DHCP"
    Write-Host "==============================="

    # ===== Validaciones =====
    function Validar-IP {
    	param([string]$ip)

    	$ip = $ip.Trim()

    	if ($ip -notmatch '^(\d{1,3}\.){3}\d{1,3}$') { return $false }

    	$octetos = $ip.Split('.')
    	foreach ($o in $octetos) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }

    	if ($ip -eq "0.0.0.0") { return $false }
    	if ($ip -eq "127.0.0.1") { return $false }
    	if ($octetos[3] -eq "0" -or $octetos[3] -eq "255") { return $false }

    	return $true
    }

    function IPaNum {
        param([string]$ip)

        $p = $ip.Split('.')

    return [uint32](
        ([uint32]$p[0] -shl 24) -bor
        ([uint32]$p[1] -shl 16) -bor
        ([uint32]$p[2] -shl 8)  -bor
        ([uint32]$p[3])
       )
    }

    # ===== Pedir rango =====
    do {
        $startIP = Read-Host "IP inicial del rango DHCP"
        if (-not (validar-ip $startIP)) { Write-Host "Error: IP no valida"; $startIP = $null }
    } until ($startIP)

    do {
        $endIP = Read-Host "IP final del rango DHCP"
        if (-not (validar-ip $endIP)) { Write-Host "Error: IP no valida"; $endIP = $null }
        elseif ((IPaNum $endIP) -lt (IPaNum $startIP)) { Write-Host "Error: IP final menor que inicial"; $endIP = $null }
    } until ($endIP)

    # ===== Calcular IP del servidor =====
    function Sumar-IP {
        param([string]$ip)

        $p = $ip.Split('.') | ForEach-Object { [int]$_ }

        $p[3]++
        if ($p[3] -gt 255) { $p[3] = 0; $p[2]++ }
        if ($p[2] -gt 255) { $p[2] = 0; $p[1]++ }
        if ($p[1] -gt 255) { $p[1] = 0; $p[0]++ }

        return "$($p[0]).$($p[1]).$($p[2]).$($p[3])"
    }

    function Calcular-IPServidor {
        param([string]$StartIP, [string]$EndIP)

        $startNum = IPaNum $StartIP
        $endNum   = IPaNum $EndIP

        $p = $StartIP.Split('.')
        $segmento = "$($p[0]).$($p[1]).$($p[2])"

        if ($startNum -lt $endNum) {
           $IPServidor  = $StartIP
           $RangoInicio = Sumar-IP $StartIP
           $RangoFin    = $EndIP
        }
        else {
           # Solo una IP disponible → el servidor no usa esa
           $IPServidor  = "$segmento.1"
           $RangoInicio = $StartIP
           $RangoFin    = $EndIP
    }

    return @{
        IPServidor  = $IPServidor
        Mascara     = 24
        RangoInicio = $RangoInicio
        RangoFin    = $RangoFin
    }
}



    $resultado = Calcular-IPServidor -StartIP $startIP -EndIP $endIP

    $IPServidor      = $resultado.IPServidor
    $Mascara         = $resultado.Mascara
    $RangoDHCPInicio = $resultado.RangoInicio
    $RangoDHCPEnd    = $resultado.RangoFin

    Write-Host "`n[ASIGNACION AUTOMATICA]"
    Write-Host "IP Servidor : $IPServidor/$Mascara"
    Write-Host "Rango DHCP  : $RangoDHCPInicio - $RangoDHCPEnd"

    # ===== Configurar IP del servidor =====
    $Adaptador = "Ethernet 2"

    Get-NetIPAddress -InterfaceAlias $Adaptador -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue *> $null

    New-NetIPAddress -InterfaceAlias $Adaptador -IPAddress $IPServidor -PrefixLength $Mascara *> $null

    # ===== Scope =====
    $scopeName = Read-Host "Nombre del Scope"

    # ===== Lease =====
    do {
        $leaseMin = Read-Host "Tiempo de concesion (minutos)"
        if (-not ($leaseMin -match '^\d+$') -or $leaseMin -le 0) { Write-Host "Error: Ingresa un numero valido"; $leaseMin = $null }
    } until ($leaseMin)

    # ===== Gateway (opcional) =====
    do {
        $gateway = Read-Host "Gateway (Enter para omitir)"
        if ($gateway -eq "") { break }
        elseif (-not (validar-ip $gateway)) { Write-Host "Error: IP gateway no valida"; $gateway = $null }
    } until ($gateway)

    # ===== DNS (opcional) =====
    do {
        $dns = Read-Host "DNS (Enter para omitir)"
        if ($dns -eq "") { break }
        elseif (-not (validar-ip $dns)) { Write-Host "Error: IP DNS no valida"; $dns = $null }
    } until ($dns)

    # ===== Crear Scope =====
    Write-Host "`n[CREANDO SCOPE DHCP]"

    Add-DhcpServerv4Scope -Name $scopeName -StartRange $RangoDHCPInicio -EndRange $RangoDHCPEnd -SubnetMask "255.255.255.0" -State Active

    if ($gateway) {
        Set-DhcpServerv4OptionValue -ScopeId $RangoDHCPInicio -Router $gateway
    }

    if ($dns) {
        Set-DhcpServerv4OptionValue -ScopeId $RangoDHCPInicio -DnsServer $dns
    }

    Set-DhcpServerv4Scope -ScopeId $RangoDHCPInicio -LeaseDuration ([TimeSpan]::FromMinutes($leaseMin))

    Write-Host "`n[OK] DHCP configurado correctamente."
}

#----------------------------------------------------------------------------------[Fin Seccion_3]

#[Seccion_4]--------------------------------------------------------------------------------------
function Monitorear-DHCP {

    Clear-Host
    echo "==========================================="
    echo "     MONITOREO DE NODOS DHCP CONECTADOS"
    echo "==========================================="

    # Estado del servicio
    $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue

    if (-not $service) {
        echo "El servicio DHCPServer no existe en este sistema."
        return
    }

    echo "`n[Estado del Servicio]"
    echo "Servicio : DHCPServer"
    echo "Estado   : $($service.Status)"
    echo "Inicio   : $($service.StartType)"

    if ($service.Status -ne "Running") {
        echo "`n⚠ El servicio no esta en ejecucion. No hay clientes activos."
        return
    }

    # Obtener scopes
    echo "`n[Scopes configurados]"
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if (-not $scopes) {
        echo "⚠ No hay Scopes configurados."
        return
    }

    foreach ($scope in $scopes) {
        echo "`n-------------------------------------------"
        echo "Scope : $($scope.Name)"
        echo "Red   : $($scope.ScopeId)"
        echo "Rango : $($scope.StartRange) - $($scope.EndRange)"

        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue

        if (-not $leases) {
            echo " No hay clientes conectados en este scope."
        } else {
            foreach ($lease in $leases) {
                echo "-------------------------------------------"
                echo "IP       : $($lease.IPAddress)"
                echo "MAC      : $($lease.ClientId)"
                echo "Host     : $($lease.HostName)"
                echo "Estado   : $($lease.AddressState)"
                echo "Expira   : $($lease.LeaseExpiryTime)"
            }
        }
    }

    echo "`nPresiona una tecla para volver al menu..."
    [System.Console]::ReadKey($true) | Out-Null
}

#----------------------------------------------------------------------------------[Fin Seccion_4]

# Configuracion del Puntero/Bandera/Menu------------------------------------

function Show-Menu {
    param([string[]]$Options)

    $index = 0
    $key = $null
    do {
        Clear-Host
	Write-Host "************************" -ForegroundColor Yellow
        Write-Host "  DHCP SERVER - MENU  " -ForegroundColor Yellow
	Write-Host "************************" -ForegroundColor Yellow

        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $index) {
                Write-Host " > $($Options[$i])" -ForegroundColor Cyan
            } else {
                Write-Host "   $($Options[$i])"
            }
        }

        $key = [System.Console]::ReadKey($true)

        switch ($key.Key) {
            "UpArrow"   { if ($index -gt 0) { $index-- } }
            "DownArrow" { if ($index -lt $Options.Count - 1) { $index++ } }
            "Enter"     { return $index }
        }

    } while ($true)
}

$menuOptions = @(
    "Estado del DHCP",
    "Instalar DHCP",
    "Configuracion del DHCP",
    "Monitoreo de nodos conectados",
    "Salir"
)

do {
    $choice = Show-Menu -Options $menuOptions

    switch ($choice) {
        0 { Estado-DHCP }
        1 { Instalar-DHCP }
        2 { Configurar-DHCP }
        3 { Monitorear-DHCP }
        4 { 
            $salir = $true 
        }
    }

    if (-not $salir) {
        Pause
    }

} while (-not $salir)
#-----------------------------------------------------------------------------
