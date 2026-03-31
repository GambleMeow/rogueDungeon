param(
    [string]$GodotExe = "godot4",
    [string]$ProjectPath = $PSScriptRoot,
    [ValidateRange(1, 10000000)]
    [int]$SteamAppId = 408,
    [string]$HostSteamId = "",
    [ValidateRange(0, 65535)]
    [int]$VirtualPort = 0
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

if ([string]::IsNullOrWhiteSpace($HostSteamId)) {
    throw "HostSteamId is required, example: -HostSteamId 7656119xxxxxxxxxx"
}

$godot = Resolve-GodotCommand -InputPathOrCommand $GodotExe

$env:SteamAppId = "$SteamAppId"
$env:SteamGameId = "$SteamAppId"

$args = @(
    "--path", $ProjectPath,
    "--",
    "--net=host",
    "--transport=steam_relay",
    "--auto-connect=true",
    "--steam-app-id=$SteamAppId",
    "--steam-id=$HostSteamId",
    "--steam-host-id=$HostSteamId",
    "--steam-virtual-port=$VirtualPort"
)

$proc = Start-Process -FilePath $godot -ArgumentList $args -PassThru

Write-Host ""
Write-Host "Steam relay host started."
Write-Host ("  PID={0}" -f $proc.Id)
Write-Host ("  SteamAppId={0}" -f $SteamAppId)
Write-Host ("  HostSteamId={0}" -f $HostSteamId)
Write-Host ("  VirtualPort={0}" -f $VirtualPort)
Write-Host ""
Write-Host ("Stop with: Stop-Process -Id {0}" -f $proc.Id)
