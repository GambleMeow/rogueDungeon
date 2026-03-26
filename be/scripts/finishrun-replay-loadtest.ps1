param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [ValidateRange(0, 100000)]
    [int]$AcceptedRuns = 20,
    [ValidateRange(0, 100000)]
    [int]$ReviewRuns = 10,
    [ValidateRange(0, 100000)]
    [int]$RejectedRuns = 10,
    [ValidateRange(2, 4)]
    [int]$PartySize = 2,
    [string]$AdminToken = $env:ADMIN_API_TOKEN,
    [string]$OutputJsonPath = "",
    [ValidateRange(1, 128)]
    [int]$Workers = 1,
    [ValidateRange(0, 1000000)]
    [int]$WorkerIndex = 0,
    [int64]$SteamOffsetSeed = 0,
    [switch]$SkipIdempotencyCase,
    [switch]$SkipQueueSnapshot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Add-Count {
    param(
        [hashtable]$Map,
        [string]$Key,
        [int]$Value = 1
    )
    if (-not $Map.ContainsKey($Key)) {
        $Map[$Key] = 0
    }
    $Map[$Key] += $Value
}

function Merge-CountMap {
    param(
        [hashtable]$Target,
        [object]$Source
    )
    if ($null -eq $Source) {
        return
    }
    foreach ($p in $Source.PSObject.Properties) {
        Add-Count -Map $Target -Key ([string]$p.Name) -Value ([int]$p.Value)
    }
}

function Split-CountEvenly {
    param(
        [int]$Total,
        [int]$Parts
    )
    $result = @()
    if ($Parts -le 0) {
        return $result
    }
    $base = [int][Math]::Floor($Total / $Parts)
    $remain = $Total % $Parts
    for ($i = 0; $i -lt $Parts; $i++) {
        $extra = if ($i -lt $remain) { 1 } else { 0 }
        $result += ($base + $extra)
    }
    return $result
}

function New-ScenarioAggregate {
    param([string]$Profile)
    return [ordered]@{
        profile = $Profile
        total = 0
        success = 0
        failed = 0
        elapsedMs = 0.0
        qps = 0.0
        latencyMs = [ordered]@{
            p50 = 0.0
            p95 = 0.0
            p99 = 0.0
        }
        httpStatus = @{}
        verdict = @{}
        rewardStatus = @{}
        sampleErrors = @()
    }
}

function Merge-ScenarioAggregate {
    param(
        [System.Collections.IDictionary]$Target,
        [object]$Part
    )
    if ($null -eq $Part) {
        return
    }
    $Target.total += [int]$Part.total
    $Target.success += [int]$Part.success
    $Target.failed += [int]$Part.failed
    $Target.elapsedMs += [double]$Part.elapsedMs
    $Target.qps += [double]$Part.qps
    if ($null -ne $Part.latencyMs) {
        $Target.latencyMs.p50 = [Math]::Max([double]$Target.latencyMs.p50, [double]$Part.latencyMs.p50)
        $Target.latencyMs.p95 = [Math]::Max([double]$Target.latencyMs.p95, [double]$Part.latencyMs.p95)
        $Target.latencyMs.p99 = [Math]::Max([double]$Target.latencyMs.p99, [double]$Part.latencyMs.p99)
    }
    Merge-CountMap -Target $Target.httpStatus -Source $Part.httpStatus
    Merge-CountMap -Target $Target.verdict -Source $Part.verdict
    Merge-CountMap -Target $Target.rewardStatus -Source $Part.rewardStatus
    $mergedErrors = @($Target.sampleErrors + @($Part.sampleErrors))
    $Target.sampleErrors = @($mergedErrors | Select-Object -First 20)
}

function Get-PowerShellExePath {
    $exeName = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }
    $candidate = Join-Path $PSHOME $exeName
    if (Test-Path $candidate) {
        return $candidate
    }
    return $exeName
}

function Get-Percentile {
    param(
        [double[]]$Values,
        [double]$Percent
    )
    if ($null -eq $Values -or $Values.Count -eq 0) {
        return 0.0
    }
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) {
        return 0.0
    }
    $idx = [int][Math]::Ceiling(($Percent / 100.0) * $sorted.Count) - 1
    if ($idx -lt 0) {
        $idx = 0
    }
    if ($idx -ge $sorted.Count) {
        $idx = $sorted.Count - 1
    }
    return [Math]::Round([double]$sorted[$idx], 2)
}

function Get-Sha256Hex {
    param([string]$InputText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText)
        $hash = $sha.ComputeHash($bytes)
        return -join ($hash | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
}

function New-SteamId {
    param([int64]$Offset)
    $base = [int64]76561198000000000
    $value = $base + $Offset
    return $value.ToString("D17")
}

function Invoke-Api {
    param(
        [string]$Method,
        [string]$Path,
        [object]$Body = $null,
        [hashtable]$Headers = @{}
    )

    $uri = if ($Path.StartsWith("http")) { $Path } else { "{0}{1}" -f $BaseUrl.TrimEnd("/"), $Path }
    $requestHeaders = @{}
    foreach ($k in $Headers.Keys) {
        $requestHeaders[$k] = $Headers[$k]
    }
    if (-not $requestHeaders.ContainsKey("Accept")) {
        $requestHeaders["Accept"] = "application/json"
    }

    $invokeParams = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $requestHeaders
        ErrorAction = "Stop"
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $invokeParams["UseBasicParsing"] = $true
    }
    if ($null -ne $Body) {
        $invokeParams["Body"] = ($Body | ConvertTo-Json -Depth 30 -Compress)
        $invokeParams["ContentType"] = "application/json"
    }

    try {
        $resp = Invoke-WebRequest @invokeParams
        $content = $resp.Content
        $parsed = $null
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            try {
                $parsed = $content | ConvertFrom-Json
            } catch {
                $parsed = $null
            }
        }
        return [PSCustomObject]@{
            StatusCode = [int]$resp.StatusCode
            Body       = $parsed
            Raw        = $content
            Error      = $null
        }
    } catch {
        $statusCode = -1
        $raw = $null

        if (-not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
            $raw = $_.ErrorDetails.Message
        }

        if ($_.Exception.PSObject.Properties.Name -contains "Response" -and $null -ne $_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode
            } catch {
                $statusCode = -1
            }

            if ([string]::IsNullOrWhiteSpace($raw)) {
                try {
                    if ($_.Exception.Response -is [System.Net.Http.HttpResponseMessage]) {
                        $raw = $_.Exception.Response.Content.ReadAsStringAsync().Result
                    } else {
                        $stream = $_.Exception.Response.GetResponseStream()
                        if ($null -ne $stream) {
                            $reader = New-Object System.IO.StreamReader($stream)
                            $raw = $reader.ReadToEnd()
                            $reader.Dispose()
                        }
                    }
                } catch {
                    $raw = $null
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($raw)) {
            $raw = $_.Exception.Message
        }

        $parsed = $null
        try {
            $parsed = $raw | ConvertFrom-Json
        } catch {
            $parsed = $null
        }

        return [PSCustomObject]@{
            StatusCode = $statusCode
            Body       = $parsed
            Raw        = $raw
            Error      = $_.Exception.Message
        }
    }
}

function Login-ForLoadTest {
    param([string]$SteamId)
    $resp = Invoke-Api -Method "POST" -Path "/v1/auth/steam/login" -Body @{
        steamId     = $SteamId
        steamTicket = ("ticket_{0}_dev" -f $SteamId)
    }
    if ($resp.StatusCode -ne 200 -or $null -eq $resp.Body -or [string]::IsNullOrWhiteSpace($resp.Body.accessToken)) {
        throw ("login failed for steamId={0}, status={1}, body={2}" -f $SteamId, $resp.StatusCode, $resp.Raw)
    }
    return [string]$resp.Body.accessToken
}

function New-Party {
    param(
        [string]$HostSteamId,
        [int]$Size,
        [int64]$Seed
    )
    $party = @(
        [ordered]@{
            steamId = $HostSteamId
            charId  = "char_host"
        }
    )
    for ($i = 1; $i -lt $Size; $i++) {
        $party += [ordered]@{
            steamId = (New-SteamId -Offset ($Seed + $i))
            charId  = ("char_{0}" -f ($i + 1))
        }
    }
    return $party
}

function Start-Run {
    param(
        [string]$AccessToken,
        [string]$HostSteamId,
        [object[]]$Party
    )
    $resp = Invoke-Api -Method "POST" -Path "/v1/runs/start" -Headers @{
        Authorization = ("Bearer {0}" -f $AccessToken)
    } -Body @{
        mode        = "rogue_coop_v1"
        difficulty  = 2
        region      = "asia-east"
        hostSteamId = $HostSteamId
        party       = $Party
        clientBuild = "loadtest-ps1"
        dlcContext  = @()
    }

    if ($resp.StatusCode -ne 200 -or $null -eq $resp.Body) {
        throw ("start run failed, status={0}, body={1}" -f $resp.StatusCode, $resp.Raw)
    }
    return [PSCustomObject]@{
        RunId        = [string]$resp.Body.runId
        RunToken     = [string]$resp.Body.runToken
        PartySteamId = @($Party | ForEach-Object { [string]$_.steamId })
    }
}

function New-ProofPayload {
    param(
        [string]$RunId,
        [object[]]$SegmentSpecs
    )
    $headHash = ("proof_head_{0}" -f ([Guid]::NewGuid().ToString("N").Substring(0, 16)))
    $prev = $headHash
    $segments = @()

    for ($idx = 0; $idx -lt $SegmentSpecs.Count; $idx++) {
        $spec = $SegmentSpecs[$idx]
        $kills = [int]$spec.kills
        $goldGain = [int]$spec.goldGain
        $damageOut = [int64]$spec.damageOut
        $damageIn = [int64]$spec.damageIn

        $payload = "{0}:{1}:{2}:{3}:{4}:{5}:{6}" -f $RunId, $idx, $kills, $goldGain, $damageOut, $damageIn, $prev
        $hash = Get-Sha256Hex -InputText $payload

        $segments += [ordered]@{
            idx       = $idx
            kills     = $kills
            goldGain  = $goldGain
            damageOut = $damageOut
            damageIn  = $damageIn
            hash      = $hash
        }
        $prev = $hash
    }

    return [ordered]@{
        segmentSec = 30
        headHash   = $headHash
        tailHash   = $prev
        segments   = $segments
    }
}

function New-FinishMembers {
    param(
        [string[]]$PartySteamIds,
        [string]$Profile
    )
    $members = @()
    for ($i = 0; $i -lt $PartySteamIds.Count; $i++) {
        $steamId = $PartySteamIds[$i]

        $rewardDraft = @(
            [ordered]@{
                type   = "soft_currency"
                id     = "gold"
                amount = 120
            },
            [ordered]@{
                type   = "item"
                id     = "shard_alpha"
                amount = 1
            }
        )

        $damageDone = 120000
        $downCount = 1
        $reviveCount = 1

        if ($Profile -eq "review") {
            $damageDone = 50000
        }
        if ($Profile -eq "rejected") {
            $damageDone = 5000000
            $downCount = 0
            $reviveCount = 10
            if ($i -eq 0) {
                $rewardDraft = @(
                    [ordered]@{
                        type   = "debug_illegal"
                        id     = "dev_drop"
                        amount = 1
                    }
                )
            }
        }

        $members += [ordered]@{
            steamId     = $steamId
            damageDone  = $damageDone
            downCount   = $downCount
            reviveCount = $reviveCount
            rewardDraft = $rewardDraft
        }
    }
    return $members
}

function New-FinishPayload {
    param(
        [string]$RunId,
        [string]$RunToken,
        [string[]]$PartySteamIds,
        [string]$Profile
    )

    switch ($Profile) {
        "accepted" {
            $final = [ordered]@{
                result       = "win"
                clearTimeSec = 420
                roomsCleared = 10
                teamScore    = 16000
                deaths       = 2
            }
            $segments = @()
            for ($i = 0; $i -lt 10; $i++) {
                $segments += [ordered]@{
                    kills     = (10 + $i)
                    goldGain  = 90
                    damageOut = (16000 + $i * 500)
                    damageIn  = (120 + $i * 5)
                }
            }
            $clientMeta = [ordered]@{
                build         = "loadtest-ps1"
                platform      = "windows"
                avgRttMs      = 48
                packetLossPct = 1.2
            }
        }
        "review" {
            $final = [ordered]@{
                result       = "win"
                clearTimeSec = 100
                roomsCleared = 10
                teamScore    = 50000
                deaths       = 1
            }
            $segments = @(
                [ordered]@{ kills = 12; goldGain = 80; damageOut = 18000; damageIn = 120 },
                [ordered]@{ kills = 10; goldGain = 75; damageOut = 17000; damageIn = 115 },
                [ordered]@{ kills = 9; goldGain = 70; damageOut = 16000; damageIn = 110 }
            )
            $clientMeta = [ordered]@{
                build         = "loadtest-ps1"
                platform      = "windows"
                avgRttMs      = 52
                packetLossPct = 1.5
            }
        }
        "rejected" {
            $final = [ordered]@{
                result       = "win"
                clearTimeSec = 1000
                roomsCleared = 2
                teamScore    = 999999
                deaths       = 0
            }
            $segments = @(
                [ordered]@{ kills = 1000; goldGain = 50000; damageOut = 900000; damageIn = 0 }
            )
            $clientMeta = [ordered]@{
                build         = "loadtest-ps1"
                platform      = "windows"
                avgRttMs      = 120
                packetLossPct = 80
            }
        }
        default {
            throw ("unknown profile: {0}" -f $Profile)
        }
    }

    return [ordered]@{
        runToken   = $RunToken
        final      = $final
        members    = (New-FinishMembers -PartySteamIds $PartySteamIds -Profile $Profile)
        proof      = (New-ProofPayload -RunId $RunId -SegmentSpecs $segments)
        clientMeta = $clientMeta
    }
}

function Invoke-Finish {
    param(
        [string]$AccessToken,
        [string]$RunId,
        [string]$IdemKey,
        [object]$Payload
    )
    return Invoke-Api -Method "POST" -Path ("/v1/runs/{0}/finish" -f $RunId) -Headers @{
        Authorization      = ("Bearer {0}" -f $AccessToken)
        "X-Idempotency-Key" = $IdemKey
    } -Body $Payload
}

function Test-ExpectedByProfile {
    param(
        [string]$Profile,
        [object]$FinishBody
    )
    if ($null -eq $FinishBody) {
        return $false
    }
    switch ($Profile) {
        "accepted" {
            return ($FinishBody.verdict -eq "accepted" -and $FinishBody.rewardStatus -eq "granted")
        }
        "review" {
            return ($FinishBody.verdict -eq "pending_review" -and $FinishBody.rewardStatus -eq "delayed")
        }
        "rejected" {
            return ($FinishBody.verdict -eq "rejected" -and $FinishBody.rewardStatus -eq "denied")
        }
        default {
            return $false
        }
    }
}

function Invoke-ScenarioBatch {
    param(
        [string]$Profile,
        [int]$Runs,
        [int64]$SteamOffsetStart
    )

    $latencies = New-Object System.Collections.Generic.List[double]
    $httpStatus = @{}
    $verdict = @{}
    $rewardStatus = @{}
    $errors = New-Object System.Collections.Generic.List[string]
    $success = 0

    $batchWatch = [System.Diagnostics.Stopwatch]::StartNew()

    $workerTag = if ($WorkerIndex -gt 0) { "worker#{0} " -f $WorkerIndex } else { "" }
    $baseOffset = $SteamOffsetStart + $SteamOffsetSeed + ([int64]$WorkerIndex * 100000000)

    for ($i = 0; $i -lt $Runs; $i++) {
        $hostSteamId = New-SteamId -Offset ($baseOffset + ($i * 100))
        $party = New-Party -HostSteamId $hostSteamId -Size $PartySize -Seed ($baseOffset + ($i * 100) + 10)

        try {
            $accessToken = Login-ForLoadTest -SteamId $hostSteamId
            $runSession = Start-Run -AccessToken $accessToken -HostSteamId $hostSteamId -Party $party
            $finishPayload = New-FinishPayload -RunId $runSession.RunId -RunToken $runSession.RunToken -PartySteamIds $runSession.PartySteamId -Profile $Profile
            $idemKey = ("load_{0}_{1}_{2}" -f $Profile, $i, [Guid]::NewGuid().ToString("N"))

            $watch = [System.Diagnostics.Stopwatch]::StartNew()
            $finishResp = Invoke-Finish -AccessToken $accessToken -RunId $runSession.RunId -IdemKey $idemKey -Payload $finishPayload
            $watch.Stop()

            $latencies.Add($watch.Elapsed.TotalMilliseconds)
            Add-Count -Map $httpStatus -Key ([string]$finishResp.StatusCode)

            if ($finishResp.StatusCode -eq 200) {
                $success++
                Add-Count -Map $verdict -Key ([string]$finishResp.Body.verdict)
                Add-Count -Map $rewardStatus -Key ([string]$finishResp.Body.rewardStatus)

                if (-not (Test-ExpectedByProfile -Profile $Profile -FinishBody $finishResp.Body)) {
                    $errors.Add(("run#{0} unexpected result verdict={1} rewardStatus={2}" -f
                            $i, $finishResp.Body.verdict, $finishResp.Body.rewardStatus))
                }
            } else {
                $errors.Add(("run#{0} finish failed status={1} body={2}" -f $i, $finishResp.StatusCode, $finishResp.Raw))
            }
        } catch {
            Add-Count -Map $httpStatus -Key "EXCEPTION"
            $errors.Add(("run#{0} exception: {1}" -f $i, $_.Exception.Message))
        }

        if ((($i + 1) % 10) -eq 0 -or ($i + 1) -eq $Runs) {
            Write-Log ("{0}{1} progress: {2}/{3}" -f $workerTag, $Profile, ($i + 1), $Runs)
        }
    }

    $batchWatch.Stop()
    $durationSec = [Math]::Max(0.001, $batchWatch.Elapsed.TotalSeconds)
    $latencyArray = @($latencies.ToArray())

    return [ordered]@{
        profile = $Profile
        total   = $Runs
        success = $success
        failed  = ($Runs - $success)
        elapsedMs = [Math]::Round($batchWatch.Elapsed.TotalMilliseconds, 2)
        qps = [Math]::Round(($Runs / $durationSec), 2)
        latencyMs = [ordered]@{
            p50 = Get-Percentile -Values $latencyArray -Percent 50
            p95 = Get-Percentile -Values $latencyArray -Percent 95
            p99 = Get-Percentile -Values $latencyArray -Percent 99
        }
        httpStatus  = $httpStatus
        verdict     = $verdict
        rewardStatus = $rewardStatus
        sampleErrors = @($errors | Select-Object -First 5)
    }
}

function Invoke-IdempotencyCase {
    param([int64]$SteamOffset)

    $hostSteamId = New-SteamId -Offset $SteamOffset
    $party = New-Party -HostSteamId $hostSteamId -Size $PartySize -Seed ($SteamOffset + 10)
    $accessToken = Login-ForLoadTest -SteamId $hostSteamId
    $runSession = Start-Run -AccessToken $accessToken -HostSteamId $hostSteamId -Party $party

    $payload = New-FinishPayload -RunId $runSession.RunId -RunToken $runSession.RunToken -PartySteamIds $runSession.PartySteamId -Profile "accepted"
    $idemKey = ("idem_case_{0}" -f [Guid]::NewGuid().ToString("N"))

    $first = Invoke-Finish -AccessToken $accessToken -RunId $runSession.RunId -IdemKey $idemKey -Payload $payload
    $second = Invoke-Finish -AccessToken $accessToken -RunId $runSession.RunId -IdemKey $idemKey -Payload $payload

    $mutated = $payload | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $mutated.final.teamScore = [int]$mutated.final.teamScore + 1
    $third = Invoke-Finish -AccessToken $accessToken -RunId $runSession.RunId -IdemKey $idemKey -Payload $mutated

    $firstOk = $first.StatusCode -eq 200
    $secondOk = $second.StatusCode -eq 200
    $sameOutput = $false
    if ($firstOk -and $secondOk) {
        $sameOutput = (
            $first.Body.verdict -eq $second.Body.verdict -and
            [int]$first.Body.riskScore -eq [int]$second.Body.riskScore -and
            $first.Body.rewardStatus -eq $second.Body.rewardStatus
        )
    }
    $mismatchOk = ($third.StatusCode -eq 409 -and $null -ne $third.Body -and $third.Body.code -eq "IDEMPOTENCY_REPLAY_MISMATCH")

    return [ordered]@{
        firstStatus  = $first.StatusCode
        replayStatus = $second.StatusCode
        mismatchStatus = $third.StatusCode
        replaySameOutput = $sameOutput
        mismatchDetected = $mismatchOk
        passed = ($firstOk -and $secondOk -and $sameOutput -and $mismatchOk)
        details = [ordered]@{
            firstBody = $first.Body
            replayBody = $second.Body
            mismatchBody = $third.Body
        }
    }
}

function Get-RewardQueueSnapshot {
    if ($SkipQueueSnapshot) {
        return [ordered]@{
            enabled = $false
            reason  = "SkipQueueSnapshot enabled"
        }
    }

    if ([string]::IsNullOrWhiteSpace($AdminToken)) {
        return [ordered]@{
            enabled = $false
            reason  = "ADMIN_API_TOKEN not provided"
        }
    }

    $headers = @{ "X-Admin-Token" = $AdminToken }
    $allStats = Invoke-Api -Method "GET" -Path "/v1/admin/reward-jobs/stats?groupBy=day&tz=UTC" -Headers $headers
    $manualPendingStats = Invoke-Api -Method "GET" -Path "/v1/admin/reward-jobs/stats?groupBy=day&tz=UTC&status=pending&manualOnly=true" -Headers $headers
    $recentManualPending = Invoke-Api -Method "GET" -Path "/v1/admin/reward-jobs?status=pending&manualOnly=true&orderBy=createdAt&order=desc&limit=5" -Headers $headers

    return [ordered]@{
        enabled = $true
        requestStatus = [ordered]@{
            allStats = $allStats.StatusCode
            manualPendingStats = $manualPendingStats.StatusCode
            recentManualPending = $recentManualPending.StatusCode
        }
        allStats = $allStats.Body
        manualPendingStats = $manualPendingStats.Body
        recentManualPending = $recentManualPending.Body
    }
}

function Get-RewardQueueDelta {
    param(
        [object]$Before,
        [object]$After
    )

    if ($null -eq $Before -or $null -eq $After) {
        return $null
    }
    if (-not $Before.enabled -or -not $After.enabled) {
        return $null
    }
    if ($null -eq $Before.allStats -or $null -eq $After.allStats) {
        return $null
    }

    $keys = @("total", "pending", "processing", "completed", "failed", "manualOnlyTrue", "manualOnlyFalse")
    $delta = [ordered]@{}
    foreach ($k in $keys) {
        $beforeVal = 0
        $afterVal = 0
        if ($Before.allStats.PSObject.Properties.Name -contains $k) {
            $beforeVal = [int]$Before.allStats.$k
        }
        if ($After.allStats.PSObject.Properties.Name -contains $k) {
            $afterVal = [int]$After.allStats.$k
        }
        $delta[$k] = ($afterVal - $beforeVal)
    }
    return $delta
}

function Invoke-ParallelWorkerMode {
    param([string]$ScriptPath)

    $acceptedSplit = Split-CountEvenly -Total $AcceptedRuns -Parts $Workers
    $reviewSplit = Split-CountEvenly -Total $ReviewRuns -Parts $Workers
    $rejectedSplit = Split-CountEvenly -Total $RejectedRuns -Parts $Workers

    $psExe = Get-PowerShellExePath
    $artifactDir = Join-Path ([System.IO.Path]::GetTempPath()) ("finishrun-workers-{0}" -f [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

    $workerProcesses = @()
    for ($i = 0; $i -lt $Workers; $i++) {
        $workerId = $i + 1
        $workerAccepted = [int]$acceptedSplit[$i]
        $workerReview = [int]$reviewSplit[$i]
        $workerRejected = [int]$rejectedSplit[$i]
        $workerSeed = $SteamOffsetSeed + ([int64]$workerId * 1000000000)

        $workerJson = Join-Path $artifactDir ("worker-{0}.json" -f $workerId)
        $workerStdOut = Join-Path $artifactDir ("worker-{0}.stdout.log" -f $workerId)
        $workerStdErr = Join-Path $artifactDir ("worker-{0}.stderr.log" -f $workerId)

        $workerArgList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $ScriptPath,
            "-BaseUrl", $BaseUrl,
            "-AcceptedRuns", $workerAccepted.ToString(),
            "-ReviewRuns", $workerReview.ToString(),
            "-RejectedRuns", $workerRejected.ToString(),
            "-PartySize", $PartySize.ToString(),
            "-Workers", "1",
            "-WorkerIndex", $workerId.ToString(),
            "-SteamOffsetSeed", $workerSeed.ToString(),
            "-SkipIdempotencyCase",
            "-SkipQueueSnapshot",
            "-OutputJsonPath", $workerJson
        )

        $proc = Start-Process -FilePath $psExe -ArgumentList $workerArgList -PassThru -WindowStyle Hidden -RedirectStandardOutput $workerStdOut -RedirectStandardError $workerStdErr
        $workerProcesses += [ordered]@{
            workerIndex = $workerId
            acceptedRuns = $workerAccepted
            reviewRuns = $workerReview
            rejectedRuns = $workerRejected
            steamOffsetSeed = $workerSeed
            outputPath = $workerJson
            stdoutPath = $workerStdOut
            stderrPath = $workerStdErr
            process = $proc
        }
    }

    $acceptedAgg = New-ScenarioAggregate -Profile "accepted"
    $reviewAgg = New-ScenarioAggregate -Profile "review"
    $rejectedAgg = New-ScenarioAggregate -Profile "rejected"
    $workerResults = @()
    $failures = New-Object System.Collections.Generic.List[string]

    foreach ($worker in $workerProcesses) {
        $proc = $worker.process
        $proc.WaitForExit()
        $exitCode = if ($null -eq $proc.ExitCode) { -1 } else { [int]$proc.ExitCode }

        $parsed = $null
        if (Test-Path $worker.outputPath) {
            try {
                $jsonRaw = Get-Content -Path $worker.outputPath -Raw -Encoding UTF8
                if (-not [string]::IsNullOrWhiteSpace($jsonRaw)) {
                    $parsed = $jsonRaw | ConvertFrom-Json
                }
            } catch {
                $parsed = $null
            }
        }

        $workerItem = [ordered]@{
            workerIndex = $worker.workerIndex
            exitCode = $exitCode
            acceptedRuns = $worker.acceptedRuns
            reviewRuns = $worker.reviewRuns
            rejectedRuns = $worker.rejectedRuns
            outputPath = $worker.outputPath
            stdoutPath = $worker.stdoutPath
            stderrPath = $worker.stderrPath
            parsed = ($null -ne $parsed)
        }

        if ($null -ne $parsed) {
            $workerItem["elapsedMs"] = [double]$parsed.elapsedMs
            Merge-ScenarioAggregate -Target $acceptedAgg -Part $parsed.scenarios.accepted
            Merge-ScenarioAggregate -Target $reviewAgg -Part $parsed.scenarios.review
            Merge-ScenarioAggregate -Target $rejectedAgg -Part $parsed.scenarios.rejected
        }

        if ($exitCode -eq -1 -and $null -ne $parsed) {
            $exitCode = 0
            $workerItem["exitCode"] = 0
        }

        if ($null -eq $parsed) {
            $failures.Add(("worker#{0} output parse failed" -f $worker.workerIndex))
        } elseif ($exitCode -ne 0) {
            $failures.Add(("worker#{0} exitCode={1}" -f $worker.workerIndex, $exitCode))
        }

        $workerResults += $workerItem
    }

    $acceptedAgg.elapsedMs = [Math]::Round([double]$acceptedAgg.elapsedMs, 2)
    $acceptedAgg.qps = [Math]::Round([double]$acceptedAgg.qps, 2)
    $reviewAgg.elapsedMs = [Math]::Round([double]$reviewAgg.elapsedMs, 2)
    $reviewAgg.qps = [Math]::Round([double]$reviewAgg.qps, 2)
    $rejectedAgg.elapsedMs = [Math]::Round([double]$rejectedAgg.elapsedMs, 2)
    $rejectedAgg.qps = [Math]::Round([double]$rejectedAgg.qps, 2)

    return [ordered]@{
        artifactDir = $artifactDir
        failures = @($failures)
        workerResults = $workerResults
        scenarios = [ordered]@{
            accepted = $acceptedAgg
            review = $reviewAgg
            rejected = $rejectedAgg
        }
    }
}

Write-Log "checking API health"
$health = Invoke-Api -Method "GET" -Path "/healthz"
if ($health.StatusCode -ne 200) {
    throw ("health check failed, status={0}, body={1}" -f $health.StatusCode, $health.Raw)
}

$totalPlanned = $AcceptedRuns + $ReviewRuns + $RejectedRuns
$mode = if ($Workers -gt 1) { "parallel" } else { "single" }
Write-Log ("load test start: accepted={0}, review={1}, rejected={2}, total={3}, partySize={4}, mode={5}, workers={6}" -f
        $AcceptedRuns, $ReviewRuns, $RejectedRuns, $totalPlanned, $PartySize, $mode, $Workers)

$globalWatch = [System.Diagnostics.Stopwatch]::StartNew()
$queueBefore = Get-RewardQueueSnapshot

if ($SkipIdempotencyCase) {
    $idempotency = [ordered]@{
        skipped = $true
        reason = "SkipIdempotencyCase enabled"
    }
} else {
    Write-Log "running idempotency conflict case"
    $idempotency = Invoke-IdempotencyCase -SteamOffset (900000 + $SteamOffsetSeed + ([int64]$WorkerIndex * 100000000))
}

$parallelMeta = $null
if ($Workers -gt 1) {
    $scriptPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        throw "cannot resolve script path for parallel worker mode"
    }
    Write-Log ("parallel worker mode enabled, launching {0} workers" -f $Workers)
    $parallelMeta = Invoke-ParallelWorkerMode -ScriptPath $scriptPath
    $accepted = $parallelMeta.scenarios.accepted
    $review = $parallelMeta.scenarios.review
    $rejected = $parallelMeta.scenarios.rejected
} else {
    $accepted = Invoke-ScenarioBatch -Profile "accepted" -Runs $AcceptedRuns -SteamOffsetStart 1000000
    $review = Invoke-ScenarioBatch -Profile "review" -Runs $ReviewRuns -SteamOffsetStart 2000000
    $rejected = Invoke-ScenarioBatch -Profile "rejected" -Runs $RejectedRuns -SteamOffsetStart 3000000
}

$queueAfter = Get-RewardQueueSnapshot
$queueDelta = Get-RewardQueueDelta -Before $queueBefore -After $queueAfter

$globalWatch.Stop()

$summary = [ordered]@{
    startedAt = (Get-Date).ToString("o")
    baseUrl = $BaseUrl
    mode = $mode
    config = [ordered]@{
        acceptedRuns = $AcceptedRuns
        reviewRuns = $ReviewRuns
        rejectedRuns = $RejectedRuns
        partySize = $PartySize
        workers = $Workers
        workerIndex = $WorkerIndex
        steamOffsetSeed = $SteamOffsetSeed
        skipIdempotencyCase = [bool]$SkipIdempotencyCase
        skipQueueSnapshot = [bool]$SkipQueueSnapshot
    }
    idempotency = $idempotency
    scenarios = [ordered]@{
        accepted = $accepted
        review = $review
        rejected = $rejected
    }
    rewardQueue = [ordered]@{
        before = $queueBefore
        after = $queueAfter
        delta = $queueDelta
    }
    elapsedMs = [Math]::Round($globalWatch.Elapsed.TotalMilliseconds, 2)
}

if ($null -ne $parallelMeta) {
    $summary["parallel"] = [ordered]@{
        artifactDir = $parallelMeta.artifactDir
        failures = $parallelMeta.failures
        workers = $parallelMeta.workerResults
    }
}

$idempotencyStatusText = "unknown"
if ($idempotency -is [System.Collections.IDictionary]) {
    if ($idempotency.Contains("passed")) {
        $idempotencyStatusText = [string]$idempotency.passed
    } elseif ($idempotency.Contains("skipped") -and [bool]$idempotency.skipped) {
        $idempotencyStatusText = "skipped"
    }
}

Write-Host ""
Write-Host "===== FinishRun Replay Load Test Summary ====="
Write-Host ("idempotency: {0}" -f $idempotencyStatusText)
Write-Host ("accepted: {0}/{1}" -f $summary.scenarios.accepted.success, $summary.scenarios.accepted.total)
Write-Host ("review:   {0}/{1}" -f $summary.scenarios.review.success, $summary.scenarios.review.total)
Write-Host ("rejected: {0}/{1}" -f $summary.scenarios.rejected.success, $summary.scenarios.rejected.total)
Write-Host ("elapsed:  {0} ms" -f $summary.elapsedMs)
if ($null -ne $parallelMeta) {
    Write-Host ("worker failures: {0}" -f @($parallelMeta.failures).Count)
}
Write-Host ""

$summaryJson = $summary | ConvertTo-Json -Depth 20
if (-not [string]::IsNullOrWhiteSpace($OutputJsonPath)) {
    $outputDir = Split-Path -Parent $OutputJsonPath
    if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
    Set-Content -Path $OutputJsonPath -Value $summaryJson -Encoding UTF8
    Write-Log ("summary written to {0}" -f $OutputJsonPath)
}

Write-Output $summaryJson
