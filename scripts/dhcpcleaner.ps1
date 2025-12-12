<# 
    DHCP lease cleaner — safe version
    - Deletes leases ONLY above 192.168.10.50
    - Does not touch reservations / filters
    - Works on all Windows Server versions
#>

$DhcpServer = "localhost"

Import-Module DhcpServer -ErrorAction Stop

$scopes = Get-DhcpServerv4Scope -ComputerName $DhcpServer

foreach ($scope in $scopes) {

    $leases = Get-DhcpServerv4Lease -ComputerName $DhcpServer -ScopeId $scope.ScopeId

    foreach ($lease in $leases) {

        $ip   = $lease.IPAddress.IPAddressToString
        $octs = $ip.Split('.')

        # Skip all addresses NOT in 192.168.10.x
        if ($octs[0] -ne "192" -or $octs[1] -ne "168" -or $octs[2] -ne "10") {
            write-host "Skipping different subnet $ip"
            continue
        }

        $last = [int]$octs[3]

        # Skip protected range 192.168.10.1–50
        if ($last -le 50) {
            write-host "Protected IP skipped: $ip"
            continue
        }

        try {
            Remove-DhcpServerv4Lease -ComputerName $DhcpServer -IPAddress $lease.IPAddress -Confirm:$false
            write-host "Removed lease: $ip"
        }
        catch {
            write-host ("Failed to remove {0}: {1}" -f $ip, $_.Exception.Message)
        }
    }
}

write-host "Done."
