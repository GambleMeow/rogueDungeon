param(
    [string]$GodotExe = "godot4",
    [string]$ProjectPath = $PSScriptRoot,
    [ValidateSet("enet", "sdr", "enet_direct", "steam_stub", "steam_relay")]
    [string]$Transport = "enet_direct",
    [string]$HostAddress = "127.0.0.1",
    [ValidateRange(1, 65535)]
    [int]$Port = 19090,
    [ValidateRange(1, 65535)]
    [int]$ClientListenPort = 19091,
    [ValidateRange(1, 10000000)]
    [int]$SteamAppId = 408,
    [string]$HostSteamId = "76561198000000001",
    [string]$ClientSteamId = "76561198000000002",
    [string]$SteamHostId = "",
    [ValidateRange(0, 10000)]
    [int]$StartupGapMs = 350
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-GodotCommand {
    param([string]$InputPathOrCommand)

    if (Test-Path $InputPathOrCommand) {
        return (Resolve-Path $InputPathOrCommand).Path
    }

    $cmd = Get-Command $InputPathOrCommand -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    throw "Godot executable not found. Pass -GodotExe <absolute path to Godot.exe>"
}

if (-not (Test-Path (Join-Path $ProjectPath "project.godot"))) {
    throw "Invalid ProjectPath: project.godot not found -> $ProjectPath"
}

$godot = Resolve-GodotCommand -InputPathOrCommand $GodotExe

if ([string]::IsNullOrWhiteSpace($SteamHostId)) {
    $SteamHostId = $HostSteamId
}

$resolvedTransport = $Transport
if ($resolvedTransport -eq "enet") {
    $resolvedTransport = "enet_direct"
}
elseif ($resolvedTransport -eq "sdr") {
    $resolvedTransport = "steam_relay"
}

$commonArgs = @(
    "--path", $ProjectPath,
    "--",
    "--auto-connect=true"
)

if ($resolvedTransport -eq "steam_stub") {
    $endpointMap = "{0}={1}:{2},{3}={1}:{4}" -f $HostSteamId, $HostAddress, $Port, $ClientSteamId, $ClientListenPort
    $hostArgs = @()
    $hostArgs += $commonArgs
    $hostArgs += @(
        "--net=host",
        "--transport=steam_stub",
        "--host=$HostAddress",
        "--port=$Port",
        "--steam-app-id=$SteamAppId",
        "--steam-id=$HostSteamId",
        "--steam-host-id=$SteamHostId",
        "--steam-listen-port=$Port",
        "--steam-remote-host=$HostAddress",
        "--steam-remote-port=$Port",
        "--steam-endpoint-map=$endpointMap"
    )

    $clientArgs = @()
    $clientArgs += $commonArgs
    $clientArgs += @(
        "--net=client",
        "--transport=steam_stub",
        "--host=$HostAddress",
        "--port=$Port",
        "--steam-app-id=$SteamAppId",
        "--steam-id=$ClientSteamId",
        "--steam-host-id=$SteamHostId",
        "--steam-listen-port=$ClientListenPort",
        "--steam-remote-host=$HostAddress",
        "--steam-remote-port=$Port",
        "--steam-endpoint-map=$endpointMap"
    )
}
elseif ($resolvedTransport -eq "steam_relay") {
    $hostArgs = @()
    $hostArgs += $commonArgs
    $hostArgs += @(
        "--net=host",
        "--transport=steam_relay",
        "--host=$SteamHostId",
        "--steam-app-id=$SteamAppId",
        "--steam-id=$HostSteamId",
        "--steam-host-id=$SteamHostId",
        "--steam-virtual-port=0"
    )

    $clientArgs = @()
    $clientArgs += $commonArgs
    $clientArgs += @(
        "--net=client",
        "--transport=steam_relay",
        "--host=$SteamHostId",
        "--steam-app-id=$SteamAppId",
        "--steam-id=$ClientSteamId",
        "--steam-host-id=$SteamHostId",
        "--steam-virtual-port=0"
    )
}
else {
    $hostArgs = @()
    $hostArgs += $commonArgs
    $hostArgs += @(
        "--net=host",
        "--transport=enet_direct",
        "--host=$HostAddress",
        "--port=$Port"
    )

    $clientArgs = @()
    $clientArgs += $commonArgs
    $clientArgs += @(
        "--net=client",
        "--transport=enet_direct",
        "--host=$HostAddress",
        "--port=$Port"
    )
}

$hostProc = Start-Process -FilePath $godot -ArgumentList $hostArgs -PassThru
if ($StartupGapMs -gt 0) {
    Start-Sleep -Milliseconds $StartupGapMs
}
$clientProc = Start-Process -FilePath $godot -ArgumentList $clientArgs -PassThru

Write-Host ''
Write-Host 'Dual instances started:'
Write-Host ('  Host   PID={0}' -f $hostProc.Id)
Write-Host ('  Client PID={0}' -f $clientProc.Id)
Write-Host ('  Transport={0}' -f $resolvedTransport)
Write-Host ('  HostAddress={0}, Port={1}, ClientListenPort={2}' -f $HostAddress, $Port, $ClientListenPort)
if ($resolvedTransport -ne "enet_direct") {
    Write-Host ('  SteamAppId={0}, SteamHostId={1}' -f $SteamAppId, $SteamHostId)
    Write-Host ('  HostSteamId={0}, ClientSteamId={1}' -f $HostSteamId, $ClientSteamId)
}
Write-Host ''
Write-Host 'To stop both:'
Write-Host ('  Stop-Process -Id {0},{1}' -f $hostProc.Id, $clientProc.Id)
