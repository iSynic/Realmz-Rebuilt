param(
    [Parameter(Mandatory)][string]$CandidatesPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$FollowUpCandidatesPath = "",
    [string]$Endpoint = "https://api.typesafe.ai/v1/systemone",
    [string]$Model = "jev-1.13.0",
    [string]$ApiKeyVariable = "TypeSafe_API_Key",
    [string]$MockResponsePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$MaxOpenCandidates = 30
$MaxControlCandidates = 10
$MaxCandidatesPerPass = 40
$MaxAttempts = 80
$CostCeilingUsd = 1.0
$InputCostPerMillionTokens = 0.042

function Get-Field($Value, [string]$Name, $Default = $null) {
    if ($null -eq $Value) { return $Default }
    if ($Value -is [Collections.IDictionary] -and $Value.Contains($Name)) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing JSON input: $Path" }
    $text = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($text)) { throw "JSON input is empty: $Path" }
    return $text | ConvertFrom-Json -AsHashtable
}

function Get-JsonHash($Value) {
    $json = $Value | ConvertTo-Json -Depth 40 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-InputIdentity([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    return [ordered]@{
        path = $resolved
        bytes = (Get-Item -LiteralPath $resolved).Length
        sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-CandidateRows($Parsed) {
    if ($Parsed -is [Collections.IDictionary] -and $Parsed.Contains("candidates")) {
        return @($Parsed["candidates"])
    }
    return @($Parsed)
}

function Convert-Candidate($Raw, [int]$Index) {
    $candidateId = [string](Get-Field $Raw "candidateId" "")
    if ([string]::IsNullOrWhiteSpace($candidateId)) { throw "Candidate $Index has no candidateId." }
    $tierValue = Get-Field $Raw "tier" 3
    if (-not (($tierValue -is [int]) -or ($tierValue -is [long]) -or ($tierValue -is [double]))) { throw "Candidate '$candidateId' has a non-numeric tier." }
    $tier = [int]$tierValue
    if ($tier -lt 1 -or $tier -gt 3) { throw "Candidate '$candidateId' tier must be 1, 2, or 3." }
    $control = [bool](Get-Field $Raw "control" $false)
    if (-not $control -and [string](Get-Field $Raw "disposition" "") -eq "adjudicated-control") { $control = $true }
    $stableIdentity = [string](Get-Field $Raw "stableIdentity" $candidateId)
    $coverageLevel = [string](Get-Field $Raw "coverageLevel" "uncertain")
    return [ordered]@{
        candidateId = $candidateId
        stableIdentity = $stableIdentity
        tier = $tier
        control = $control
        scenario = [string](Get-Field $Raw "scenario" "")
        source = [string](Get-Field $Raw "source" "")
        ap = [string](Get-Field $Raw "ap" "")
        program = [string](Get-Field $Raw "program" "")
        slot = Get-Field $Raw "slot" $null
        behaviorFamily = [string](Get-Field $Raw "behaviorFamily" "")
        coverageLevel = $coverageLevel
        callerChain = Get-Field $Raw "callerChain" @()
        suspectedDefect = [string](Get-Field $Raw "suspectedDefect" "")
        evidence = Get-Field $Raw "evidence" @()
        preparation = Get-Field $Raw "preparation" @()
        expectedOutcome = [string](Get-Field $Raw "expectedOutcome" "")
        proofMode = [string](Get-Field $Raw "proofMode" "")
        status = [string](Get-Field $Raw "status" "open")
        originalIndex = $Index
    }
}

function Convert-CandidateForState($Candidate) {
    $result = [ordered]@{}
    foreach ($name in @("candidateId", "stableIdentity", "tier", "scenario", "source", "ap", "program", "slot", "behaviorFamily", "coverageLevel", "callerChain", "suspectedDefect", "evidence", "preparation", "proofMode")) {
        $result[$name] = $Candidate[$name]
    }
    if (-not [bool]$Candidate.control) {
        $result["expectedOutcome"] = $Candidate.expectedOutcome
        $result["status"] = $Candidate.status
    }
    return $result
}

function New-JevRequest($Candidate) {
    $state = [ordered]@{
        task = "Rank one scenario-audit candidate for the next evidence workflow."
        rules = @(
            "Use only the supplied candidate metadata and evidence summary.",
            "A higher score means more additional behavioral coverage, not higher bug severity.",
            "Keep the priority tier fixed; Jev may order candidates only within that tier.",
            "Do not infer closure or parity from a successful compile or an unverified claim."
        )
        candidate = Convert-CandidateForState $Candidate
    }
    return [ordered]@{
        state = $state
        model = $Model
        questions = [ordered]@{
            coverageScore = [ordered]@{
                type = "score"
                instructions = "How much additional observable behavior would the next workflow cover for this candidate? Score the candidate itself, not the confidence in the evidence."
                criteria = @(
                    "Already covered behavior",
                    "Uncovered parameter or outcome variant",
                    "Uncovered caller or continuation",
                    "Distinct untested behavior family"
                )
            }
            evidenceChoice = [ordered]@{
                type = "choice"
                instructions = "What evidence should be gathered next to decide this candidate? Choose the smallest adequate proof mode, or insufficient-information when the supplied metadata cannot identify one."
                criteria = [ordered]@{
                    "source-inspection" = "Inspect the pinned native source, imported records, or compiler projection."
                    "session-fixture" = "Use an isolated Debug Runtime Testing Bridge fixture or direct callee invocation."
                    "ordinary-movement" = "Use ordinary movement or a caller route to prove trigger reachability."
                    "visible-ui" = "Use real visible controls and input routing to prove a UI claim."
                    "castle-trace" = "Use a controlled Castle trace because source alone cannot settle the observable behavior."
                    "insufficient-information" = "The candidate lacks enough information to choose a responsible proof mode."
                }
            }
        }
    }
}

function Get-ResponseError($Kind, [string]$Message, $StatusCode = $null) {
    return [ordered]@{ kind = $Kind; message = $Message; statusCode = $StatusCode }
}

function Test-Number($Value) {
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) -and [double]::IsFinite([double]$Value)
}

function Test-ModelResponse($Body) {
    if (-not ($Body -is [Collections.IDictionary]) -or -not $Body.Contains("answers") -or -not $Body.Contains("usage")) {
        return Get-ResponseError "malformed_response" "The response omitted answers or usage."
    }
    $answers = $Body.answers
    if (-not ($answers -is [Collections.IDictionary]) -or -not $answers.Contains("coverageScore") -or -not $answers.Contains("evidenceChoice")) {
        return Get-ResponseError "malformed_response" "The response omitted one of the required Score or Choice answers."
    }
    $score = $answers.coverageScore
    $choice = $answers.evidenceChoice
    if (-not ($score -is [Collections.IDictionary]) -or $score.type -ne "score" -or -not (Test-Number $score.score) -or -not (Test-Number $score.confidence) -or -not ($score.probabilities -is [Collections.IDictionary])) {
        return Get-ResponseError "malformed_response" "The coverageScore answer is not a valid Score response."
    }
    if (-not ($choice -is [Collections.IDictionary]) -or $choice.type -ne "choice" -or -not ($choice.choice -is [string]) -or -not (Test-Number $choice.confidence) -or -not ($choice.probabilities -is [Collections.IDictionary])) {
        return Get-ResponseError "malformed_response" "The evidenceChoice answer is not a valid Choice response."
    }
    $validChoices = @("source-inspection", "session-fixture", "ordinary-movement", "visible-ui", "castle-trace", "insufficient-information")
    if ($choice.choice -notin $validChoices) { return Get-ResponseError "malformed_response" "The Choice answer selected an unsupported proof mode." }
    foreach ($probability in $score.probabilities.Values + $choice.probabilities.Values) {
        if (-not (Test-Number $probability) -or [double]$probability -lt 0 -or [double]$probability -gt 1) {
            return Get-ResponseError "malformed_response" "A returned probability was outside 0 through 1."
        }
    }
    $usage = $Body.usage
    if (-not ($usage -is [Collections.IDictionary]) -or -not (Test-Number $usage.input_tokens) -or -not (Test-Number $usage.output_tokens)) {
        return Get-ResponseError "malformed_response" "The response usage object is invalid."
    }
    return $null
}

function Get-ScoreExpected($Answer) {
    $expected = 0.0
    foreach ($key in $Answer.probabilities.Keys) { $expected += [double]$key * [double]$Answer.probabilities[$key] }
    return $expected
}

function Invoke-JevHttp($Request, [string]$ApiKey, [int]$AttemptNumber) {
    $requestJson = $Request | ConvertTo-Json -Depth 40 -Compress
    $requestHash = Get-JsonHash $Request
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri $Endpoint -Method Post -Headers @{ Authorization = "Bearer $ApiKey" } -ContentType "application/json" -Body $requestJson
        $clock.Stop()
        $body = $response.Content | ConvertFrom-Json -AsHashtable
        return [ordered]@{ ok = $true; body = $body; requestHash = $requestHash; latencyMs = $clock.ElapsedMilliseconds; statusCode = [int]$response.StatusCode; attempt = $AttemptNumber }
    } catch {
        $clock.Stop()
        $statusCode = $null
        if ($null -ne $_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        return [ordered]@{ ok = $false; error = Get-ResponseError "service_failure" "TypeSafe request failed." $statusCode; requestHash = $requestHash; latencyMs = $clock.ElapsedMilliseconds; statusCode = $statusCode; attempt = $AttemptNumber }
    }
}

function Get-MockResponse($Mock, [string]$CandidateId) {
    if ($Mock -is [Collections.IDictionary] -and $Mock.Contains("responses")) { $Mock = $Mock.responses }
    if ($Mock -is [Collections.IDictionary] -and $Mock.Contains($CandidateId)) { return $Mock[$CandidateId] }
    foreach ($row in @($Mock)) {
        if ([string](Get-Field $row "candidateId" "") -eq $CandidateId) { return Get-Field $row "response" $row }
    }
    return $null
}

function Invoke-Candidate($Candidate, $Mock, [ref]$Attempts, [ref]$SpentUsd) {
    $request = New-JevRequest $Candidate
    $requestHash = Get-JsonHash $request
    if ($null -ne $Mock) {
        $body = Get-MockResponse $Mock $Candidate.candidateId
        if ($null -eq $body) {
            return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; requestHash = $requestHash; error = Get-ResponseError "mock_missing" "No mocked response was supplied."; attempts = 0 }
        }
        $validation = Test-ModelResponse $body
        if ($null -ne $validation) {
            return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; requestHash = $requestHash; error = $validation; attempts = 0 }
        }
        $inputTokens = [int]$body.usage.input_tokens
        $SpentUsd.Value += $inputTokens / 1000000.0 * $InputCostPerMillionTokens
        $scoreAnswer = $body.answers.coverageScore
        $choiceAnswer = $body.answers.evidenceChoice
        return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; model = [string](Get-Field $body "model" $Model); requestHash = $requestHash; inputTokens = $inputTokens; outputTokens = [int]$body.usage.output_tokens; estimatedCostUsd = $inputTokens / 1000000.0 * $InputCostPerMillionTokens; latencyMs = 0; attempts = 0; score = [double]$scoreAnswer.score; scoreExpected = Get-ScoreExpected $scoreAnswer; scoreProbabilities = $scoreAnswer.probabilities; scoreConfidence = [double]$scoreAnswer.confidence; choice = $choiceAnswer.choice; choiceProbabilities = $choiceAnswer.probabilities; choiceConfidence = [double]$choiceAnswer.confidence }
    }
    if ($DryRun) {
        return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; requestHash = $requestHash; dryRun = $true; requestBytes = ($request | ConvertTo-Json -Depth 40 -Compress).Length; attempts = 0 }
    }
    if ($Attempts.Value -ge $MaxAttempts) {
        return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; requestHash = $requestHash; error = Get-ResponseError "attempt_limit" "The Jev attempt limit was reached."; attempts = 0 }
    }
    $last = $null
    for ($retry = 0; $retry -lt 3; $retry++) {
        if ($Attempts.Value -ge $MaxAttempts) { break }
        $Attempts.Value++
        $reply = Invoke-JevHttp $request $ApiKey $Attempts.Value
        if ($reply.ok) {
            $validation = Test-ModelResponse $reply.body
            if ($null -eq $validation) {
                $inputTokens = [int]$reply.body.usage.input_tokens
                $cost = $inputTokens / 1000000.0 * $InputCostPerMillionTokens
                $SpentUsd.Value += $cost
                $scoreAnswer = $reply.body.answers.coverageScore
                $choiceAnswer = $reply.body.answers.evidenceChoice
                return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; model = [string](Get-Field $reply.body "model" $Model); requestHash = $requestHash; inputTokens = $inputTokens; outputTokens = [int]$reply.body.usage.output_tokens; estimatedCostUsd = $cost; latencyMs = $reply.latencyMs; statusCode = $reply.statusCode; attempts = $retry + 1; score = [double]$scoreAnswer.score; scoreExpected = Get-ScoreExpected $scoreAnswer; scoreProbabilities = $scoreAnswer.probabilities; scoreConfidence = [double]$scoreAnswer.confidence; choice = $choiceAnswer.choice; choiceProbabilities = $choiceAnswer.probabilities; choiceConfidence = [double]$choiceAnswer.confidence }
            }
            return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; requestHash = $requestHash; latencyMs = $reply.latencyMs; statusCode = $reply.statusCode; attempts = $retry + 1; error = $validation }
        }
        $last = $reply
        $statusCode = $reply.statusCode
        if ($statusCode -notin @(429, 529)) { break }
        Start-Sleep -Milliseconds ([int]([math]::Min(4000, 250 * [math]::Pow(2, $retry))))
    }
    return [ordered]@{ candidateId = $Candidate.candidateId; stableIdentity = $Candidate.stableIdentity; tier = $Candidate.tier; pass = $PassName; requestHash = $requestHash; latencyMs = if ($null -ne $last) { $last.latencyMs } else { 0 }; statusCode = if ($null -ne $last) { $last.statusCode } else { $null }; attempts = if ($null -ne $last) { $last.attempt } else { 0 }; error = if ($null -ne $last) { $last.error } else { Get-ResponseError "service_unavailable" "The TypeSafe service was not contacted." } }
}

function Get-ApiKey() {
    foreach ($scope in @("Process", "User")) {
        $value = [Environment]::GetEnvironmentVariable($ApiKeyVariable, $scope)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    if ($ApiKeyVariable -eq "TypeSafe_API_Key") {
        foreach ($scope in @("Process", "User")) {
            $value = [Environment]::GetEnvironmentVariable("TYPESAFE_API_KEY", $scope)
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    }
    return $null
}

$initialInput = Get-InputIdentity $CandidatesPath
$initialParsed = Read-Json $CandidatesPath
$initialCandidates = @(Get-CandidateRows $initialParsed | ForEach-Object -Begin { $index = 0 } -Process { $row = Convert-Candidate $_ $index; $index++; $row })
$followUpCandidates = @()
$followUpInput = $null
if (-not [string]::IsNullOrWhiteSpace($FollowUpCandidatesPath)) {
    $followUpInput = Get-InputIdentity $FollowUpCandidatesPath
    $followUpParsed = Read-Json $FollowUpCandidatesPath
    $followUpCandidates = @(Get-CandidateRows $followUpParsed | ForEach-Object -Begin { $index = 0 } -Process { $row = Convert-Candidate $_ $index; $index++; $row })
}

foreach ($passCandidates in @($initialCandidates, $followUpCandidates)) {
    if (@($passCandidates).Count -gt $MaxCandidatesPerPass) { throw "A Jev pass contains more than $MaxCandidatesPerPass candidates." }
    if (@($passCandidates | Where-Object { -not $_.control }).Count -gt $MaxOpenCandidates) { throw "A Jev pass contains more than $MaxOpenCandidates open candidates." }
    if (@($passCandidates | Where-Object { $_.control }).Count -gt $MaxControlCandidates) { throw "A Jev pass contains more than $MaxControlCandidates adjudicated controls." }
}

$mock = $null
if (-not [string]::IsNullOrWhiteSpace($MockResponsePath)) { $mock = Read-Json $MockResponsePath }
$ApiKey = if ($DryRun -or $null -ne $mock) { $null } else { Get-ApiKey }
$Attempts = 0
$SpentUsd = 0.0
$allResults = @()
$passNumber = 0
foreach ($passCandidates in @($initialCandidates, $followUpCandidates)) {
    if (@($passCandidates).Count -eq 0) { continue }
    $passNumber++
    $PassName = if ($passNumber -eq 1) { "initial" } else { "affected-follow-up" }
    $orderedCandidates = @($passCandidates | Sort-Object @{Expression={ [int]$_.tier }}, @{Expression={ [string]$_.stableIdentity }}, @{Expression={ [int]$_.originalIndex }})
    foreach ($candidate in $orderedCandidates) {
        if ($SpentUsd -ge $CostCeilingUsd -and $null -eq $mock -and -not $DryRun) {
            $allResults += [ordered]@{ candidateId = $candidate.candidateId; stableIdentity = $candidate.stableIdentity; tier = $candidate.tier; pass = $PassName; error = Get-ResponseError "cost_ceiling" "The Jev cost ceiling was reached before this candidate."; attempts = 0 }
            continue
        }
        if ($null -eq $mock -and -not $DryRun -and [string]::IsNullOrWhiteSpace($ApiKey)) {
            $allResults += [ordered]@{ candidateId = $candidate.candidateId; stableIdentity = $candidate.stableIdentity; tier = $candidate.tier; pass = $PassName; error = Get-ResponseError "credentials_unavailable" "No TypeSafe API key was found in the configured user environment."; attempts = 0 }
            continue
        }
        $allResults += Invoke-Candidate $candidate $mock ([ref]$Attempts) ([ref]$SpentUsd)
    }
}

$valid = @($allResults | Where-Object { $null -eq $_.error -and $null -ne $_.scoreExpected })
$jevRankings = @($valid | Group-Object -Property @{ Expression = { [int]$_.tier } } | ForEach-Object {
    [ordered]@{
        tier = [int]$_.Name
        candidates = @($_.Group | Sort-Object @{Expression={ -[double]$_.scoreExpected }}, @{Expression={ [string]$_.stableIdentity }} | ForEach-Object { $_.candidateId })
    }
})
$deterministicQueue = @($initialCandidates | Sort-Object @{Expression={ [int]$_.tier }}, @{Expression={ [string]$_.stableIdentity }}, @{Expression={ [int]$_.originalIndex }} | ForEach-Object { $_.candidateId })
$report = [ordered]@{
    kind = "realmz-rebuilt.scenario-audit-jev-ranking"
    formatVersion = 1
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    modelRequested = $Model
    endpoint = $Endpoint
    inputs = [ordered]@{ initial = $initialInput; followUp = $followUpInput }
    limits = [ordered]@{ maxOpenCandidates = $MaxOpenCandidates; maxControlCandidates = $MaxControlCandidates; maxCandidatesPerPass = $MaxCandidatesPerPass; maxAttempts = $MaxAttempts; costCeilingUsd = $CostCeilingUsd }
    mode = if ($DryRun) { "dry-run" } elseif ($null -ne $mock) { "mock" } else { "live" }
    attempts = $Attempts
    estimatedCostUsd = [math]::Round($SpentUsd, 8)
    serviceAvailable = -not [bool](@($allResults | Where-Object { $_.error.kind -eq "credentials_unavailable" -or $_.error.kind -eq "service_failure" }).Count)
    results = $allResults
    deterministicQueue = $deterministicQueue
    jevRankingsWithinTier = $jevRankings
    adoption = "suggestions-only; deterministic tiered queue and evidence review remain authoritative"
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolvedOutput)) | Out-Null
[IO.File]::WriteAllText($resolvedOutput, ($report | ConvertTo-Json -Depth 60), [Text.UTF8Encoding]::new($false))
Write-Host "Jev candidate ranking report: $resolvedOutput"
