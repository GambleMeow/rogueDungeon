param(
    [string]$GodotExe = "godot4",
    [string]$ProjectPath = $PSScriptRoot,
    [string]$RunId = "local_test_001",
    [ValidateRange(0, 10000)]
    [int]$StartupGapMs = 350,
    [switch]$UseSimulatedTransport
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
$transport = if ($UseSimulatedTransport) { "simulated" } else { "steam_stub" }

$hostArgs = @(
    "--path", $ProjectPath,
    "--",
    "--instance=host",
    "--run-id=$RunId",
    "--transport=$transport",
    "--backend=false",
    "--auto-start=true"
)

$clientArgs = @(
    "--path", $ProjectPath,
    "--",
    "--instance=client",
    "--run-id=$RunId",
    "--transport=$transport",
    "--backend=false",
    "--auto-start=true"
)

$hostProc = Start-Process -FilePath $godot -ArgumentList $hostArgs -PassThru
if ($StartupGapMs -gt 0) {
    Start-Sleep -Milliseconds $StartupGapMs
}
$clientProc = Start-Process -FilePath $godot -ArgumentList $clientArgs -PassThru

Write-Host ''
Write-Host 'Dual instances started:'
Write-Host ('  Host   PID={0}' -f $hostProc.Id)
Write-Host ('  Client PID={0}' -f $clientProc.Id)
Write-Host ('  RunId={0}, transport={1}' -f $RunId, $transport)
Write-Host ''
Write-Host 'To stop both:'
Write-Host ('  Stop-Process -Id {0},{1}' -f $hostProc.Id, $clientProc.Id)
