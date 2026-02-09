echo " DHCP SERVER "

$dhcp = Get-WindowsFeature -Name DHCP

if (-not $dhcp.Installed) {
    echo "[+] Instalando rol DHCP..."
    Install-WindowsFeature DHCP -IncludeManagementTools
} else {
    echo "[-] DHCP ya esta instalado."
}

function validar-ip {
    param([string]$ip)
    if ($ip -match '^(\d{1,3}\.){3}\d{1,3}$') {
        $octetos = $ip.Split('.')
        foreach ($o in $octetos) {
            if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
        }
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

$AdaptadorInterno = "Ethernet 2"
$IPServidor = "192.168.100.1"
$Mascara = 24

Get-NetIPAddress -InterfaceAlias $AdaptadorInterno -AddressFamily IPv4 -ErrorAction SilentlyContinue |
Remove-NetIPAddress -Confirm:$false

New-NetIPAddress `
 -InterfaceAlias $AdaptadorInterno `
 -IPAddress $IPServidor `
 -PrefixLength $Mascara

$MIN_IP = "192.168.100.50"
$MAX_IP = "192.168.100.150"

$scopeName = Read-Host "Nombre del Scope"

do {
    $startIP = Read-Host "IP inicial (>= $MIN_IP)"
} until (validar-ip $startIP -and en-red $startIP -and ((IPaNum $startIP) -ge (IPaNum $MIN_IP)))

do {
    $endIP = Read-Host "IP Final (<= $MAX_IP)"
} until (validar-ip $endIP -and en-red $endIP -and ((IPaNum $endIP) -le (IPaNum $MAX_IP)))

if ((IPaNum $startIP) -ge (IPaNum $endIP)) {
    echo "Error: IP/s no validas"
    exit
}

$lease = Read-Host "Tiempo de Concesion (en Horas)"

do {
    $gateway = Read-Host "Gateway"
} until (validar-ip $gateway -and en-red $gateway)

do {
    $dns = Read-Host "DNS"
} until (validar-ip $dns)
