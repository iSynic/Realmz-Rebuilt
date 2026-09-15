param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $PackagePath,
    [string] $ApplicationPackagePath = (Join-Path $PSScriptRoot "../src/storage/packages/application/realmz-classic-application-library.realmz2"),
    [string] $OutputPath = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Read-ZipJson {
    param(
        [System.IO.Compression.ZipArchive] $Archive,
        [string] $EntryName
    )
    $entry = $Archive.Entries | Where-Object FullName -eq $EntryName | Select-Object -First 1
    if ($null -eq $entry) {
        throw "Package is missing $EntryName."
    }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
        return $reader.ReadToEnd() | ConvertFrom-Json
    }
    finally {
        $reader.Dispose()
    }
}

function Add-ProgramTarget {
    param(
        [System.Collections.Generic.HashSet[string]] $Targets,
        [int] $Id
    )
    if ($Id -ge 0) {
        [void] $Targets.Add("xap:$Id")
    }
}

function Add-InlineEncounterTargets {
    param(
        [System.Collections.Generic.HashSet[string]] $Targets,
        [string] $Kind,
        [int] $Id
    )
    if ($Id -lt 0) {
        return
    }
    foreach ($result in 0..3) {
        [void] $Targets.Add("${Kind}:${Id}:result:${result}")
    }
}

function Add-ZeroBasedBranchTarget {
    param(
        [System.Collections.Generic.HashSet[string]] $Targets,
        [int] $Mode,
        [int] $Id
    )
    switch ($Mode) {
        0 { Add-ProgramTarget $Targets $Id }
        1 { Add-InlineEncounterTargets $Targets "simple" $Id }
        2 { Add-InlineEncounterTargets $Targets "complex" $Id }
    }
}

function Add-OneBasedBranchTarget {
    param(
        [System.Collections.Generic.HashSet[string]] $Targets,
        [int] $Mode,
        [int] $Id
    )
    switch ($Mode) {
        1 { Add-ProgramTarget $Targets $Id }
        2 { Add-InlineEncounterTargets $Targets "simple" $Id }
        3 { Add-InlineEncounterTargets $Targets "complex" $Id }
    }
}

function Add-ForceBranchTarget {
    param(
        [System.Collections.Generic.HashSet[string]] $Targets,
        [int] $Mode,
        [int] $Id,
        [string] $OwnerKind,
        [int] $OwnerId
    )
    switch ($Mode) {
        0 { Add-ProgramTarget $Targets $Id }
        1 {
            if ($OwnerKind -eq "simple-encounter-result" -and $Id -ge 0 -and $Id -le 3) {
                [void] $Targets.Add("simple:${OwnerId}:result:${Id}")
            }
        }
        2 {
            if ($OwnerKind -eq "complex-encounter-result" -and $Id -ge 0 -and $Id -le 3) {
                [void] $Targets.Add("complex:${OwnerId}:result:${Id}")
            }
        }
    }
}

function Add-ChoiceBranchTarget {
    param(
        [System.Collections.Generic.HashSet[string]] $Targets,
        [int] $Mode,
        [int] $Id,
        [string] $OwnerKind,
        [int] $OwnerId
    )
    switch ($Mode) {
        1 { Add-ProgramTarget $Targets $Id }
        2 { Add-ForceBranchTarget $Targets 1 $Id $OwnerKind $OwnerId }
        3 { Add-ForceBranchTarget $Targets 2 $Id $OwnerKind $OwnerId }
    }
}

function Get-ProgramTargets {
    param([pscustomobject] $Program)

    $targets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $ownerKind = [string] $Program.ownerKind
    $ownerId = -1
    if ([string] $Program.id -match '^(?:simple|complex):(\d+):result:\d+$') {
        $ownerId = [int] $Matches[1]
    }
    foreach ($action in @($Program.instructions)) {
        if ([string] $action.kind -ne "classicAction") {
            continue
        }
        $opcode = [int] $action.opcode
        $id = [int] $action.id
        $extra = @($action.extraCode)
        if ($opcode -eq 39) {
            Add-ProgramTarget $targets $id
            continue
        }
        if ($opcode -eq 4) {
            Add-InlineEncounterTargets $targets "simple" $id
            continue
        }
        if ($opcode -eq 5) {
            Add-InlineEncounterTargets $targets "complex" $id
            continue
        }
        if ($extra.Count -lt 5) {
            continue
        }
        $e = @($extra | ForEach-Object { [int] $_ })
        switch ($opcode) {
            2 { if ($e[4] -eq 10) { Add-ProgramTarget $targets $e[2] } }
            3 { Add-ChoiceBranchTarget $targets $e[1] $e[2] $ownerKind $ownerId }
            7 { Add-ProgramTarget $targets $e[2] }
            21 {
                Add-ZeroBasedBranchTarget $targets $e[1] $e[3]
                if ($e[2] -eq 0) { Add-ZeroBasedBranchTarget $targets $e[1] $e[4] }
            }
            31 { Add-ProgramTarget $targets $e[3]; Add-ProgramTarget $targets $e[4] }
            38 { Add-ForceBranchTarget $targets $e[2] $e[3] $ownerKind $ownerId }
            40 { Add-OneBasedBranchTarget $targets $e[1] $e[2] }
            42 { Add-ForceBranchTarget $targets $e[2] $e[3] $ownerKind $ownerId }
            46 { Add-ForceBranchTarget $targets $e[2] $e[3] $ownerKind $ownerId }
            55 {
                Add-ProgramTarget $targets $e[3]
                if ($e[1] -eq 1) { Add-ProgramTarget $targets $e[4] }
            }
            56 { Add-ProgramTarget $targets $e[2] }
            58 { Add-ForceBranchTarget $targets $e[2] $e[3] $ownerKind $ownerId }
            59 { Add-ForceBranchTarget $targets $e[2] $e[3] $ownerKind $ownerId }
            64 { Add-ProgramTarget $targets $e[3]; Add-ProgramTarget $targets $e[4] }
            67 { Add-ZeroBasedBranchTarget $targets $e[1] $e[3]; Add-ZeroBasedBranchTarget $targets $e[1] $e[4] }
            72 { Add-ZeroBasedBranchTarget $targets $e[3] $e[4] }
            75 { Add-ZeroBasedBranchTarget $targets $e[3] $e[4] }
            76 { if ($e[3] -ne 0) { Add-OneBasedBranchTarget $targets $e[2] $e[4] } }
            77 {
                if ($e[3] -ne 0) { Add-ZeroBasedBranchTarget $targets $e[2] $e[3] }
                if ($e[4] -ne 0) { Add-ZeroBasedBranchTarget $targets $e[2] $e[4] }
            }
            78 {
                if ($e[3] -ne 0) { Add-ZeroBasedBranchTarget $targets $e[2] $e[3] }
                if ($e[4] -ne 0) { Add-ZeroBasedBranchTarget $targets $e[2] $e[4] }
            }
            81 { Add-ProgramTarget $targets $e[3]; Add-ProgramTarget $targets $e[4] }
            85 {
                if ($e[2] -ge $e[1]) {
                    foreach ($targetId in $e[1]..$e[2]) { Add-ZeroBasedBranchTarget $targets $e[0] $targetId }
                }
            }
            86 {
                if ($e[3] -ne 0) { Add-ZeroBasedBranchTarget $targets $e[2] $e[3] }
                if ($e[4] -ne 0) { Add-ZeroBasedBranchTarget $targets $e[2] $e[4] }
            }
            87 {
                Add-ZeroBasedBranchTarget $targets $e[1] $e[3]
                if ($e[2] -eq 0) { Add-ZeroBasedBranchTarget $targets $e[1] $e[4] }
            }
            107 { Add-ProgramTarget $targets $e[4] }
            126 {
                if ($e[2] -eq 2 -and $e[4] -ge $e[3]) {
                    foreach ($targetId in $e[3]..$e[4]) { Add-ProgramTarget $targets $targetId }
                }
                else { Add-ProgramTarget $targets $e[3] }
            }
        }
    }
    return @($targets | Sort-Object)
}

function Get-MacroSpellDisposition {
    param([pscustomobject] $Spell)
    if ($null -eq $Spell) { return "missing-spell" }
    if ([int] $Spell.queueIcon -ne 0) { return "queued-field" }
    if ([int] $Spell.targetType -eq 0) { return "repeated-target" }
    if ([int] $Spell.targetType -in @(3, 4, 9, 10, 12)) { return "executable-immediate" }
    return "unsupported-target"
}

$packages = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($candidate in $PackagePath) {
    $item = Get-Item -LiteralPath $candidate
    if ($item.PSIsContainer) {
        foreach ($package in Get-ChildItem -LiteralPath $item.FullName -Filter *.realmz2 -File) {
            $packages.Add($package)
        }
    }
    else {
        $packages.Add($item)
    }
}

$applicationSpells = @{}
$applicationPackage = Get-Item -LiteralPath $ApplicationPackagePath
$applicationArchive = [System.IO.Compression.ZipFile]::OpenRead($applicationPackage.FullName)
try {
    $applicationContent = Read-ZipJson $applicationArchive "content.json"
    foreach ($spell in @($applicationContent.spells)) { $applicationSpells[[int] $spell.classicId] = $spell }
}
finally {
    $applicationArchive.Dispose()
}

$results = @()
foreach ($package in @($packages | Sort-Object FullName -Unique)) {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($package.FullName)
    try {
        $scenario = Read-ZipJson $archive "scenario.json"
        $content = Read-ZipJson $archive "content.json"
        $programs = @{}
        foreach ($program in @($scenario.programs)) { $programs[[string] $program.id] = $program }
        $availableXapIds = @($programs.Keys | Where-Object { $_ -match '^xap:(\d+)$' } | ForEach-Object { [int] $Matches[1] })
        $maximumAvailableXapId = if ($availableXapIds.Count -eq 0) { -1 } else { [int] ($availableXapIds | Measure-Object -Maximum).Maximum }
        $spells = @{}
        foreach ($entry in $applicationSpells.GetEnumerator()) { $spells[$entry.Key] = $entry.Value }
        foreach ($spell in @($content.spells)) { $spells[[int] $spell.classicId] = $spell }

        $battleRoots = @($content.battles | Where-Object { [int] $_.macroId -lt 0 } | ForEach-Object { "xap:$([Math]::Abs([int] $_.macroId))" } | Sort-Object -Unique)
        $deathRoots = @($content.monsters | Where-Object { [int] $_.deathMacro -gt 0 } | ForEach-Object { "xap:$([int] $_.deathMacro)" } | Sort-Object -Unique)
        $roots = @($battleRoots + $deathRoots | Sort-Object -Unique)
        $pending = [System.Collections.Generic.Queue[string]]::new()
        foreach ($root in $roots) { $pending.Enqueue($root) }
        $reachable = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $missingPrograms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        while ($pending.Count -gt 0) {
            $programId = $pending.Dequeue()
            if (-not $reachable.Add($programId)) { continue }
            if (-not $programs.ContainsKey($programId)) {
                [void] $missingPrograms.Add($programId)
                continue
            }
            foreach ($target in Get-ProgramTargets $programs[$programId]) {
                if (-not $reachable.Contains($target)) { $pending.Enqueue($target) }
            }
        }

        $stored = @()
        $reachableRows = @()
        foreach ($program in @($scenario.programs)) {
            foreach ($action in @($program.instructions)) {
                if ([string] $action.kind -ne "classicAction" -or [int] $action.opcode -ne 17) { continue }
                $extra = @($action.extraCode)
                $spellId = if ($extra.Count -gt 0) { [int] $extra[0] } else { -1 }
                $spell = if ($spells.ContainsKey($spellId)) { $spells[$spellId] } else { $null }
                $row = [ordered]@{
                    programId = [string] $program.id
                    spellId = $spellId
                    targetType = if ($null -eq $spell) { $null } else { [int] $spell.targetType }
                    queueIcon = if ($null -eq $spell) { $null } else { [int] $spell.queueIcon }
                    disposition = Get-MacroSpellDisposition $spell
                }
                $stored += [pscustomobject] $row
                if ($reachable.Contains([string] $program.id)) { $reachableRows += [pscustomobject] $row }
            }
        }
        $manifest = Read-ZipJson $archive "manifest.json"
        $missingWithinProgramExtent = @($missingPrograms | Where-Object {
            $_ -match '^xap:(\d+)$' -and [int] $Matches[1] -le $maximumAvailableXapId
        } | Sort-Object)
        $missingBeyondProgramExtent = @($missingPrograms | Where-Object {
            $_ -notmatch '^xap:(\d+)$' -or [int] $Matches[1] -gt $maximumAvailableXapId
        } | Sort-Object)
        $results += [pscustomobject] [ordered]@{
            package = $package.Name
            campaignId = [string] $manifest.campaignId
            packageSha256 = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            battleMacroRoots = $battleRoots
            deathMacroRoots = $deathRoots
            reachableProgramCount = $reachable.Count
            maximumAvailableXapId = $maximumAvailableXapId
            missingPrograms = @($missingPrograms | Sort-Object)
            missingWithinProgramExtent = $missingWithinProgramExtent
            missingBeyondProgramExtent = $missingBeyondProgramExtent
            storedOpcode17 = $stored
            reachableOpcode17 = $reachableRows
        }
    }
    finally {
        $archive.Dispose()
    }
}

$report = [pscustomobject] [ordered]@{
    schemaVersion = 2
    semantics = "Static authored call reachability from negative battle macros and positive monster death macros. Missing calls are separated by the greatest emitted XAP identity; that structural split does not establish source validity, controlled execution, or ordinary-route reachability."
    applicationPackageSha256 = (Get-FileHash -LiteralPath $applicationPackage.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    packageCount = $results.Count
    packages = $results
}
$json = $report | ConvertTo-Json -Depth 12
if ([string]::IsNullOrEmpty($OutputPath)) {
    $json
}
else {
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    [System.IO.File]::WriteAllText($resolved, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}
