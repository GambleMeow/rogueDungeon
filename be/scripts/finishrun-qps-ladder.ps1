param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [ValidateRange(0, 1000000)]
    [int]$AcceptedRuns = 200,
    [ValidateRange(0, 1000000)]
    [int]$ReviewRuns = 100,
    [ValidateRange(0, 1000000)]
    [int]$RejectedRuns = 100,
    [ValidateRange(2, 4)]
    [int]$PartySize = 4,
    [string]$WorkersLadder = "2,4,8,16",
    [string]$AdminToken = $env:ADMIN_API_TOKEN,
    [string]$OutputJsonPath = ".\scripts\out\finishrun-qps-ladder.json",
    [ValidateRange(0, 300)]
    [int]$CooldownSec = 1,
    [switch]$RunIdempotencyCase,
    [switch]$SkipQueueSnapshotInSteps,
    [switch]$KeepStepReports
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Parse-WorkersLadder {
    param([string]$Raw)
    $parts = @($Raw -split "[,; ]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0) {
        throw "WorkersLadder is empty"
    }

    $workers = New-Object System.Collections.Generic.List[int]
    foreach ($p in $parts) {
        $parsed = 0
        if (-not [int]::TryParse($p, [ref]$parsed)) {
            throw ("invalid worker count: {0}" -f $p)
        }
        if ($parsed -lt 1 -or $parsed -gt 128) {
            throw ("worker count out of range [1,128]: {0}" -f $parsed)
        }
        $workers.Add($parsed)
    }
    return @($workers | Sort-Object -Unique)
}

function Ensure-ParentDir {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Get-Prop {
    param(
        [object]$Obj,
        [string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $Obj) {
        return $Default
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) {
        return $Obj.$Name
    }
    return $Default
}

function To-Int {
    param([object]$Value)
    if ($null -eq $Value) {
        return 0
    }
    try {
        return [int]$Value
    } catch {
        return 0
    }
}

function To-Double {
    param([object]$Value)
    if ($null -eq $Value) {
        return 0.0
    }
    try {
        return [double]$Value
    } catch {
        return 0.0
    }
}

function Get-ScenarioSummary {
    param([object]$Scenario)
    $latency = Get-Prop -Obj $Scenario -Name "latencyMs" -Default $null
    return [ordered]@{
        total = To-Int (Get-Prop -Obj $Scenario -Name "total" -Default 0)
        success = To-Int (Get-Prop -Obj $Scenario -Name "success" -Default 0)
        failed = To-Int (Get-Prop -Obj $Scenario -Name "failed" -Default 0)
        qps = To-Double (Get-Prop -Obj $Scenario -Name "qps" -Default 0)
        p95 = To-Double (Get-Prop -Obj $latency -Name "p95" -Default 0)
    }
}

$workers = Parse-WorkersLadder -Raw $WorkersLadder
$totalRuns = $AcceptedRuns + $ReviewRuns + $RejectedRuns
if ($totalRuns -le 0) {
    throw "AcceptedRuns + ReviewRuns + RejectedRuns must be > 0"
}

$singleScriptPath = Join-Path $PSScriptRoot "finishrun-replay-loadtest.ps1"
if (-not (Test-Path $singleScriptPath)) {
    throw ("missing script: {0}" -f $singleScriptPath)
}

Write-Log ("ladder start workers={0} totalRunsPerStep={1}" -f ($workers -join ","), $totalRuns)

$ladderId = [Guid]::NewGuid().ToString("N")
$stepDir = Join-Path ([System.IO.Path]::GetTempPath()) ("finishrun-ladder-{0}" -f $ladderId)
New-Item -ItemType Directory -Path $stepDir -Force | Out-Null

$steps = @()
$artifactDirs = New-Object System.Collections.Generic.List[string]
$overallWatch = [System.Diagnostics.Stopwatch]::StartNew()

for ($idx = 0; $idx -lt $workers.Count; $idx++) {
    $workerCount = [int]$workers[$idx]
    $stepPath = Join-Path $stepDir ("step-workers-{0}.json" -f $workerCount)
    $stepParams = @{
        BaseUrl = $BaseUrl
        AcceptedRuns = $AcceptedRuns
        ReviewRuns = $ReviewRuns
        RejectedRuns = $RejectedRuns
        PartySize = $PartySize
        Workers = $workerCount
        OutputJsonPath = $stepPath
    }
    if (-not [string]::IsNullOrWhiteSpace($AdminToken)) {
        $stepParams["AdminToken"] = $AdminToken
    }
    if (-not $RunIdempotencyCase) {
        $stepParams["SkipIdempotencyCase"] = $true
    }
    if ($SkipQueueSnapshotInSteps) {
        $stepParams["SkipQueueSnapshot"] = $true
    }

    Write-Log ("step workers={0} start" -f $workerCount)
    $stepWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stepExitCode = 0
    $stepError = ""

    try {
        & $singleScriptPath @stepParams | Out-Null
    } catch {
        $stepExitCode = 1
        $stepError = $_.Exception.Message
    }
    $stepWatch.Stop()

    $stepData = $null
    if (Test-Path $stepPath) {
        try {
            $raw = Get-Content -Path $stepPath -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $stepData = $raw | ConvertFrom-Json
            } else {
                if ($stepExitCode -eq 0) {
                    $stepExitCode = 2
                    $stepError = "step output json is empty"
                }
            }
        } catch {
            if ($stepExitCode -eq 0) {
                $stepExitCode = 3
                $stepError = ("step output parse failed: {0}" -f $_.Exception.Message)
            }
        }
    } else {
        if ($stepExitCode -eq 0) {
            $stepExitCode = 4
            $stepError = "step output json not found"
        }
    }

    $accepted = Get-ScenarioSummary -Scenario (Get-Prop -Obj (Get-Prop -Obj $stepData -Name "scenarios" -Default $null) -Name "accepted" -Default $null)
    $review = Get-ScenarioSummary -Scenario (Get-Prop -Obj (Get-Prop -Obj $stepData -Name "scenarios" -Default $null) -Name "review" -Default $null)
    $rejected = Get-ScenarioSummary -Scenario (Get-Prop -Obj (Get-Prop -Obj $stepData -Name "scenarios" -Default $null) -Name "rejected" -Default $null)

    $runTotal = $accepted.total + $review.total + $rejected.total
    $runSuccess = $accepted.success + $review.success + $rejected.success
    $runFailed = $accepted.failed + $review.failed + $rejected.failed

    $elapsedMs = To-Double (Get-Prop -Obj $stepData -Name "elapsedMs" -Default $stepWatch.Elapsed.TotalMilliseconds)
    if ($elapsedMs -lt 0.001) {
        $elapsedMs = 0.001
    }
    $overallQps = [Math]::Round(($runTotal / ($elapsedMs / 1000.0)), 2)
    $maxP95 = [Math]::Round([Math]::Max([Math]::Max($accepted.p95, $review.p95), $rejected.p95), 2)
    $errorRatePct = if ($runTotal -gt 0) { [Math]::Round(($runFailed * 100.0) / $runTotal, 2) } else { 100.0 }

    $parallel = Get-Prop -Obj $stepData -Name "parallel" -Default $null
    $parallelFailures = @(Get-Prop -Obj $parallel -Name "failures" -Default @())
    $parallelFailureCount = $parallelFailures.Count
    $parallelArtifactDir = [string](Get-Prop -Obj $parallel -Name "artifactDir" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($parallelArtifactDir)) {
        $artifactDirs.Add($parallelArtifactDir)
    }

    $status = if ($stepExitCode -eq 0 -and $runFailed -eq 0 -and $parallelFailureCount -eq 0 -and $runSuccess -eq $runTotal -and $runTotal -gt 0) { "pass" } else { "fail" }

    $steps += [ordered]@{
        workers = $workerCount
        status = $status
        runTotal = $runTotal
        runSuccess = $runSuccess
        runFailed = $runFailed
        errorRatePct = $errorRatePct
        elapsedMs = [Math]::Round($elapsedMs, 2)
        overallQps = $overallQps
        maxP95Ms = $maxP95
        accepted = $accepted
        review = $review
        rejected = $rejected
        stepExitCode = $stepExitCode
        parallelFailureCount = $parallelFailureCount
        parallelFailures = $parallelFailures
        stepError = $stepError
        stepReportPath = $stepPath
    }

    Write-Log ("step workers={0} done status={1} qps={2} fail={3}" -f $workerCount, $status, $overallQps, $runFailed)

    if ($CooldownSec -gt 0 -and $idx -lt ($workers.Count - 1)) {
        Start-Sleep -Seconds $CooldownSec
    }
}

$overallWatch.Stop()

$passSteps = @($steps | Where-Object { $_.status -eq "pass" })
$bestQpsStep = $null
if ($steps.Count -gt 0) {
    $bestQpsStep = @($steps | Sort-Object -Property overallQps -Descending | Select-Object -First 1)[0]
}

$maxStableWorkers = 0
if ($passSteps.Count -gt 0) {
    $maxStableWorkers = [int](@($passSteps | Sort-Object -Property workers -Descending | Select-Object -First 1)[0].workers)
}

$recommendation = [ordered]@{
    maxStableWorkers = $maxStableWorkers
    bestQpsWorkers = if ($null -ne $bestQpsStep) { [int]$bestQpsStep.workers } else { 0 }
    bestQps = if ($null -ne $bestQpsStep) { [double]$bestQpsStep.overallQps } else { 0.0 }
    note = if ($maxStableWorkers -gt 0) { "use maxStableWorkers as current safe upper bound" } else { "no stable step found, check step errors" }
}

$summary = [ordered]@{
    startedAt = (Get-Date).ToString("o")
    baseUrl = $BaseUrl
    config = [ordered]@{
        acceptedRuns = $AcceptedRuns
        reviewRuns = $ReviewRuns
        rejectedRuns = $RejectedRuns
        partySize = $PartySize
        workersLadder = $workers
        cooldownSec = $CooldownSec
        runIdempotencyCase = [bool]$RunIdempotencyCase
        skipQueueSnapshotInSteps = [bool]$SkipQueueSnapshotInSteps
    }
    recommendation = $recommendation
    steps = $steps
    elapsedMs = [Math]::Round($overallWatch.Elapsed.TotalMilliseconds, 2)
}

Write-Host ""
Write-Host "===== FinishRun QPS Ladder ====="
foreach ($step in $steps) {
    Write-Host ("workers={0} status={1} success={2}/{3} qps={4} p95(max)={5}ms errRate={6}%" -f
            $step.workers, $step.status, $step.runSuccess, $step.runTotal, $step.overallQps, $step.maxP95Ms, $step.errorRatePct)
}
Write-Host ("maxStableWorkers={0}, bestQpsWorkers={1}, bestQps={2}" -f
        $recommendation.maxStableWorkers, $recommendation.bestQpsWorkers, $recommendation.bestQps)
Write-Host ""

$summaryJson = $summary | ConvertTo-Json -Depth 30
Ensure-ParentDir -Path $OutputJsonPath
Set-Content -Path $OutputJsonPath -Value $summaryJson -Encoding UTF8
Write-Log ("ladder summary written: {0}" -f $OutputJsonPath)

if (-not $KeepStepReports) {
    foreach ($step in $steps) {
        if (Test-Path $step.stepReportPath) {
            Remove-Item -Path $step.stepReportPath -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($dir in ($artifactDirs | Sort-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path $dir)) {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $stepDir) {
        Remove-Item -Path $stepDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output $summaryJson
