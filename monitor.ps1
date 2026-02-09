echo "=== CLIENTES DHCP CONECTADOS ==="

$scopes = Get-DhcpServerv4Scope

foreach ($scope in $scopes) {
    Write-Host "`nScope:" $scope.Name " - " $scope.ScopeId

    $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId

    if ($leases.Count -eq 0) {
        Write-Host "  No hay clientes conectados."
    } else {
        foreach ($lease in $leases) {
            Write-Host "-----------------------------------"
            Write-Host "IP       :" $lease.IPAddress
            Write-Host "MAC      :" $lease.ClientId
            Write-Host "Host     :" $lease.HostName
            Write-Host "Expira   :" $lease.LeaseExpiryTime
        }
    }
}
