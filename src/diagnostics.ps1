# WINDOWS IT SUPPORT DIAGNOSTICS TOOLKIT
# Version: 1.3 | Windows PowerShell 5.1+

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# MODULE 1: SYSTEM INFORMATION
function Get-SystemInformation {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.LastBootUpTime
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            OperatingSystem = $os.Caption
            Version = $os.Version
            BuildNumber = $os.BuildNumber
            LastBootTime = $os.LastBootUpTime
            Uptime = '{0} days, {1} hours' -f $uptime.Days, $uptime.Hours
        }
    }
    catch {
        Write-Warning "System information collection failed: $($_.Exception.Message)"
        [PSCustomObject]@{ Status = 'Failed'; Details = $_.Exception.Message }
    }
}

# MODULE 2: NETWORK INFORMATION
function Get-NetworkInformation {
    try {
        $adapters = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.NetAdapter.Status -eq 'Up' })
        if ($adapters.Count -eq 0) {
            return [PSCustomObject]@{ Status = 'No active network adapters found' }
        }
        foreach ($adapter in $adapters) {
            [PSCustomObject]@{
                InterfaceAlias = $adapter.InterfaceAlias
                IPv4Address = (($adapter.IPv4Address | ForEach-Object { $_.IPAddress }) -join ', ')
                DefaultGateway = (($adapter.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ', ')
                DNSServers = (($adapter.DnsServer.ServerAddresses) -join ', ')
            }
        }
    }
    catch {
        Write-Warning "Network information collection failed: $($_.Exception.Message)"
        [PSCustomObject]@{ Status = 'Failed'; Details = $_.Exception.Message }
    }
}

# MODULE 3: CONNECTIVITY DIAGNOSTICS
function Get-ConnectivityDiagnostics {
    try {
        $config = Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } | Select-Object -First 1
        if (-not $config) { throw 'No active IPv4 network gateway found.' }
        $gateway = $config.IPv4DefaultGateway.NextHop
        $gatewayPing = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
        $publicIP = '1.1.1.1'
        $publicIPPing = Test-Connection -ComputerName $publicIP -Count 2 -Quiet -ErrorAction SilentlyContinue
        $dnsSuccess = $false
        $resolvedIPs = ''
        try {
            $dnsRecords = Resolve-DnsName -Name 'google.com' -Type A -ErrorAction Stop
            $resolvedIPs = (($dnsRecords | Where-Object { $_.IPAddress } | Select-Object -ExpandProperty IPAddress) -join ', ')
            $dnsSuccess = -not [string]::IsNullOrWhiteSpace($resolvedIPs)
        }
        catch { $dnsSuccess = $false }
        $tcpSuccess = Test-NetConnection -ComputerName $publicIP -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Gateway = $gateway
            GatewayPing = [bool]$gatewayPing
            PublicIP = $publicIP
            PublicIPPing = [bool]$publicIPPing
            DNSResolution = [bool]$dnsSuccess
            ResolvedIPv4 = $resolvedIPs
            TCPPort443 = [bool]$tcpSuccess
        }
    }
    catch {
        Write-Warning "Connectivity diagnostics failed: $($_.Exception.Message)"
        [PSCustomObject]@{ Status = 'Failed'; Details = $_.Exception.Message }
    }
}

# MODULE 4: WINDOWS SERVICES DIAGNOSTICS
function Get-ServiceDiagnostics {
    $serviceNames = @('BITS', 'Spooler', 'wuauserv', 'Dhcp', 'Audiosrv')
    try {
        $allServices = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
        foreach ($serviceName in $serviceNames) {
            $service = $allServices | Where-Object { $_.Name -eq $serviceName } | Select-Object -First 1
            if ($null -ne $service) {
                [PSCustomObject]@{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    State = $service.State
                    StartMode = $service.StartMode
                    StartName = $service.StartName
                    ProcessId = $service.ProcessId
                    ExitCode = $service.ExitCode
                }
            }
            else {
                [PSCustomObject]@{ Name = $serviceName; DisplayName = 'Not found'; State = 'Unknown'; StartMode = 'Unknown'; StartName = 'Unknown'; ProcessId = 0; ExitCode = 'N/A' }
            }
        }
    }
    catch {
        Write-Warning "Service diagnostics failed: $($_.Exception.Message)"
        [PSCustomObject]@{ Status = 'Failed'; Details = $_.Exception.Message }
    }
}

# MODULE 5: EVENT VIEWER DIAGNOSTICS
function Get-EventLogDiagnostics {
    $filter = @{ LogName = 'System'; ProviderName = 'Service Control Manager'; StartTime = (Get-Date).AddHours(-24); Level = @(2, 3) }
    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents 20 -ErrorAction Stop)
        if ($events.Count -eq 0) { return [PSCustomObject]@{ Status = 'No matching events found in the last 24 hours.' } }
        foreach ($event in $events) {
            [PSCustomObject]@{ TimeCreated = $event.TimeCreated; EventID = $event.Id; Level = $event.LevelDisplayName; Source = $event.ProviderName; Message = $event.Message }
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -like '*NoMatchingEventsFound*') {
            [PSCustomObject]@{ Status = 'No matching events found in the last 24 hours.' }
        }
        else {
            Write-Warning "Event log query failed: $($_.Exception.Message)"
            [PSCustomObject]@{ Status = 'Query failed'; Details = $_.Exception.Message }
        }
    }
}

# MODULE 6: AUTOMATIC TXT REPORT
function New-DiagnosticsReport {
    param(
        [object[]]$SystemInfo, [object[]]$NetworkInfo, [object[]]$ConnectivityInfo,
        [object[]]$ServiceInfo, [object[]]$EventInfo
    )
    try {
        $reportDirectory = Join-Path $ProjectRoot 'reports'
        if (-not (Test-Path -LiteralPath $reportDirectory)) {
            New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $reportPath = Join-Path $reportDirectory "Diagnostics_$timestamp.txt"
        $sections = @(
            'WINDOWS IT SUPPORT DIAGNOSTICS REPORT'
            ("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))
            ("Computer: {0}" -f $env:COMPUTERNAME)
            ('=' * 70)
            'MODULE 1 - SYSTEM INFORMATION'
            (($SystemInfo | Format-List | Out-String -Width 200).TrimEnd())
            ('=' * 70)
            'MODULE 2 - NETWORK INFORMATION'
            (($NetworkInfo | Format-List | Out-String -Width 200).TrimEnd())
            ('=' * 70)
            'MODULE 3 - CONNECTIVITY DIAGNOSTICS'
            (($ConnectivityInfo | Format-List | Out-String -Width 200).TrimEnd())
            ('=' * 70)
            'MODULE 4 - WINDOWS SERVICES'
            (($ServiceInfo | Format-Table -AutoSize | Out-String -Width 200).TrimEnd())
            ('=' * 70)
            'MODULE 5 - EVENT VIEWER DIAGNOSTICS'
            (($EventInfo | Format-List | Out-String -Width 200).TrimEnd())
            ('=' * 70)
            'END OF REPORT'
        )
        $sections -join [Environment]::NewLine | Set-Content -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop
        [PSCustomObject]@{ Status = 'Report saved'; ReportPath = $reportPath }
    }
    catch {
        Write-Warning "Report generation failed: $($_.Exception.Message)"
        [PSCustomObject]@{ Status = 'Report generation failed'; Details = $_.Exception.Message }
    }
}

# MAIN: RUN ALL DIAGNOSTICS
Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '       WINDOWS IT SUPPORT DIAGNOSTICS TOOLKIT       ' -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host "`n=== MODULE 1: SYSTEM INFORMATION ===" -ForegroundColor Yellow
$systemInfo = @(Get-SystemInformation)
$systemInfo | Format-List
Write-Host "`n=== MODULE 2: NETWORK INFORMATION ===" -ForegroundColor Yellow
$networkInfo = @(Get-NetworkInformation)
$networkInfo | Format-List
Write-Host "`n=== MODULE 3: CONNECTIVITY DIAGNOSTICS ===" -ForegroundColor Yellow
$connectivityInfo = @(Get-ConnectivityDiagnostics)
$connectivityInfo | Format-List
Write-Host "`n=== MODULE 4: WINDOWS SERVICES ===" -ForegroundColor Yellow
$serviceInfo = @(Get-ServiceDiagnostics)
$serviceInfo | Format-Table -AutoSize
Write-Host "`n=== MODULE 5: EVENT VIEWER DIAGNOSTICS ===" -ForegroundColor Yellow
$eventInfo = @(Get-EventLogDiagnostics)
$eventInfo | Format-List
Write-Host "`n=== MODULE 6: REPORT GENERATOR ===" -ForegroundColor Yellow
$reportResult = New-DiagnosticsReport -SystemInfo $systemInfo -NetworkInfo $networkInfo -ConnectivityInfo $connectivityInfo -ServiceInfo $serviceInfo -EventInfo $eventInfo
$reportResult | Format-List
Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '                DIAGNOSTICS COMPLETED              ' -ForegroundColor Green
Write-Host '====================================================' -ForegroundColor Cyan