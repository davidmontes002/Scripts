Write-Host "Bienvenido"
$hostname = $env:COMPUTERNAME
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).IPAddress
$disk = Get-PSDrive -PSProvider FileSystem

Write-Host "Nombre del equipo: $hostname"
Write-Host "IP actual: $ip"
Write-Host "Espacio en disco: "
$disk | ForEach-Object {
    [PSCustomObject]@{
        Unidad = $_.Name
        UsadoGB = [math]::Round($_.Used / 1GB, 2)
        LibreGB = [math]::Round($_.Free / 1GB, 2)
        TotalGB = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
    }
} | Format-Table -AutoSize
