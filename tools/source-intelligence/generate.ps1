[CmdletBinding()]
param(
    [switch]$ValidateOnly,
    [string]$GeneratedAt = ""
)

$ErrorActionPreference = "Stop"
$generatorVersion = "1.0.2"
$scriptDirectory = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path (Join-Path $scriptDirectory "..\..")).Path
$outputRoot = Join-Path $repoRoot "docs\codemap"
$catalogPath = Join-Path $scriptDirectory "catalog.json"
$templatePath = Join-Path $scriptDirectory "codemap.template.html"
$generatedNames = @("codemap.html", "codemap.json", "intelligence.json", "chunks.jsonl", "codemap.lock")
$scopeRoots = @("src", "tests", "tools", "docs", "contracts", ".github")
$rootFiles = @("AGENTS.md", "README.md", ".gitignore", ".gitattributes", ".mcp.json", "project.godot", "export_presets.cfg")
$excludedDirectoryText = @(
    ".git", ".godot", ".references", "references", "artifacts", "vendor", "build", "dist", "cache",
    "exports", "generated", "node_modules", "target", "out", "bin", "obj", "addons/godot_mcp"
)
$textExtensions = @(
    ".gd", ".ps1", ".md", ".json", ".sha256", ".yml", ".yaml", ".godot", ".cfg",
    ".tscn", ".txt", ".toml", ".ini", ".gitignore"
)

function Get-RelativeRepoPath {
    param([string]$FullPath)
    return (([IO.Path]::GetRelativePath($repoRoot, $FullPath)) -replace "\\", "/")
}

function Test-IndexedPath {
    param([string]$RelativePath)
    $path = $RelativePath -replace "\\", "/"
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    if ($path -match "(^|/)(\.git|\.godot|\.references|references|artifacts|vendor|build|dist|cache|exports|generated|node_modules|target|out|bin|obj|addons/godot_mcp)(/|$)") { return $false }
    if ($path -match "\.uid$") { return $false }
    if ($path -match "\.(realmz2|zip|png|jpg|jpeg|gif|bmp|wav|ogg|mp3|mp4|avi|exe|dll|so|dylib|pck)$") { return $false }
    if ($path -like "docs/codemap/*" -and $generatedNames -contains ([IO.Path]::GetFileName($path))) { return $false }
    $leaf = [IO.Path]::GetFileName($path)
    if ($path -notmatch "/" -and $rootFiles -contains $leaf) { return $true }
    if ($path -match "^\.github/" -or $path -match "^(src|tests|tools|docs|contracts)/") {
        $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
        return $textExtensions -contains $extension -or $leaf -eq "AGENTS.md"
    }
    return $false
}

function Get-InputPaths {
    $listed = @(git -C $repoRoot ls-files --cached --others --exclude-standard)
    return @($listed |
        ForEach-Object { ($_ -replace "\\", "/").Trim() } |
        Where-Object { Test-IndexedPath $_ } |
        Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot ($_ -replace "/", "\")) -PathType Leaf } |
        Sort-Object -Unique)
}

function Get-Sha256Bytes {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (([BitConverter]::ToString($sha.ComputeHash($Bytes))) -replace "-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-CanonicalJson {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Read-Utf8Text {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
}

function Get-WorkingTreeHasUncommittedChanges {
    $statusLines = @(git -C $repoRoot status --porcelain --untracked-files=all)
    foreach ($statusLine in $statusLines) {
        $statusPath = ([string]$statusLine).Substring(3).Trim() -replace "\\", "/"
        if ($statusPath -match "^(?:.* -> )?docs/codemap/(?:\.stage-[^/]+/|codemap\.html$|codemap\.json$|codemap\.lock$|intelligence\.json$|chunks\.jsonl$)") {
            continue
        }
        return $true
    }
    return $false
}

function Test-CommitsHaveSameIndexedInputs {
    param(
        [string]$LeftCommit,
        [string]$RightCommit,
        [string[]]$Paths
    )
    if ([string]::IsNullOrWhiteSpace($LeftCommit) -or [string]::IsNullOrWhiteSpace($RightCommit)) { return $false }
    $arguments = @("-C", $repoRoot, "diff", "--quiet", "--no-ext-diff", $LeftCommit, $RightCommit, "--") + $Paths
    & git @arguments
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw "Unable to compare indexed inputs between commits '$LeftCommit' and '$RightCommit'."
}

function Get-CanonicalGeneratedAt {
    param([object]$Value)
    if ($null -eq $Value) { return "" }
    if ($Value -is [DateTimeOffset]) {
        return $Value.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [DateTime]) {
        return ([DateTimeOffset]$Value).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    try {
        $parsed = [DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
        return $parsed.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $text
    }
}

function Get-TextFileRecord {
    param([string]$RelativePath, [string]$Commit)
    $fullPath = Join-Path $repoRoot ($RelativePath -replace "/", "\")
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try {
        $content = $utf8.GetString($bytes)
    } catch {
        return [ordered]@{
            id = "file:$RelativePath"
            path = $RelativePath
            sha256 = (Get-Sha256Bytes $bytes)
            line_count = 0
            content = ""
            bytes = $bytes
            lines = @()
            module_id = $null
            dox_scope_id = $null
            encoding_error = $_.Exception.Message
        }
    }
    $lines = [regex]::Split($content, "\r\n|\n|\r")
    return [ordered]@{
        id = "file:$RelativePath"
        path = $RelativePath
        sha256 = (Get-Sha256Bytes $bytes)
        line_count = $lines.Count
        content = $content
        bytes = $bytes
        lines = $lines
        module_id = $null
        dox_scope_id = $null
    }
}

function Get-PathEvidence {
    param([object]$File, [string]$Commit, [string]$Symbol = "")
    $startText = if ($File.lines.Count -gt 0) { [string]$File.lines[0] } else { "" }
    $endText = if ($File.lines.Count -gt 0) { [string]$File.lines[$File.lines.Count - 1] } else { "" }
    return [ordered]@{
        path = $File.path
        symbol = $Symbol
        start_line = 1
        start_column = 1
        end_line = [Math]::Max(1, [int]$File.line_count)
        end_column = [Math]::Max(1, $endText.Length + 1)
        file_sha256 = $File.sha256
        commit = $Commit
        source_kind = "filesystem"
        text = $startText.Trim()
    }
}

function Get-SourceSpan {
    param(
        [object]$File,
        [int]$StartLine,
        [string]$Symbol,
        [int]$EndLine = 0,
        [int]$StartColumn = 0,
        [int]$EndColumn = 0,
        [string]$Commit,
        [string]$SourceKind = "source"
    )
    if ($EndLine -le 0) { $EndLine = $StartLine }
    $EndLine = [Math]::Min([Math]::Max(1, $EndLine), [Math]::Max(1, $File.lines.Count))
    $lineText = if ($StartLine -ge 1 -and $StartLine -le $File.lines.Count) { [string]$File.lines[$StartLine - 1] } else { "" }
    if ($StartColumn -le 0) {
        $found = if ([string]::IsNullOrEmpty($Symbol)) { -1 } else { $lineText.IndexOf($Symbol, [StringComparison]::Ordinal) }
        $StartColumn = if ($found -ge 0) { $found + 1 } else { 1 }
    }
    if ($EndColumn -le 0) {
        $endLineText = [string]$File.lines[$EndLine - 1]
        $EndColumn = [Math]::Max(1, $endLineText.Length + 1)
    }
    return [ordered]@{
        path = $File.path
        symbol = $Symbol
        start_line = $StartLine
        start_column = $StartColumn
        end_line = $EndLine
        end_column = $EndColumn
        file_sha256 = $File.sha256
        commit = $Commit
        source_kind = $SourceKind
        text = $lineText.Trim()
    }
}

function Get-CatalogSpan {
    param([string]$Commit, [string]$Symbol)
    $catalogBytes = [IO.File]::ReadAllBytes($catalogPath)
    $catalogHash = Get-Sha256Bytes $catalogBytes
    $catalogText = [Text.UTF8Encoding]::new($false, $true).GetString($catalogBytes)
    $catalogLines = [regex]::Split($catalogText, "\r\n|\n|\r")
    $lineNumber = 1
    $column = 1
    for ($i = 0; $i -lt $catalogLines.Count; $i++) {
        $found = ([string]$catalogLines[$i]).IndexOf($Symbol, [StringComparison]::Ordinal)
        if ($found -ge 0) { $lineNumber = $i + 1; $column = $found + 1; break }
    }
    if ($lineNumber -eq 1 -and ([string]$catalogLines[0]).IndexOf($Symbol, [StringComparison]::Ordinal) -lt 0) { throw "Catalog evidence symbol not found: $Symbol" }
    return [ordered]@{
        path = "tools/source-intelligence/catalog.json"
        symbol = $Symbol
        start_line = $lineNumber
        start_column = $column
        end_line = $lineNumber
        end_column = $column + [Math]::Max(1, $Symbol.Length)
        file_sha256 = $catalogHash
        commit = $Commit
        source_kind = "catalog"
        text = ([string]$catalogLines[$lineNumber - 1]).Trim()
    }
}

function New-Slug {
    param([string]$Text)
    $slug = $Text.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")
    if ([string]::IsNullOrEmpty($slug)) { return "section" }
    return $slug
}

function Get-NearestDoxId {
    param([string]$RelativePath, [hashtable]$FileByPath)
    $dir = [IO.Path]::GetDirectoryName($RelativePath) -replace "\\", "/"
    while ($true) {
        $candidate = if ([string]::IsNullOrEmpty($dir)) { "AGENTS.md" } else { "$dir/AGENTS.md" }
        if ($FileByPath.ContainsKey($candidate)) { return "dox:$candidate" }
        if ([string]::IsNullOrEmpty($dir)) { break }
        $next = [IO.Path]::GetDirectoryName($dir) -replace "\\", "/"
        if ($next -eq $dir) { break }
        $dir = $next
    }
    return $null
}

function Get-ModuleIdForPath {
    param([string]$RelativePath, [object[]]$CatalogNodes)
    $best = $null
    foreach ($node in ($CatalogNodes | Sort-Object { ([string]$_.path).Length } -Descending)) {
        $nodePath = ([string]$node.path).TrimEnd("/")
        if ($RelativePath -eq $nodePath -or $RelativePath.StartsWith("$nodePath/", [StringComparison]::OrdinalIgnoreCase)) {
            $best = "module:$($node.id)"
            break
        }
    }
    if ($best) { return $best }
    $top = ($RelativePath -split "/")[0]
    if ($top -eq ".github") { return "module:workflows" }
    if ($top -in @("docs", "contracts", "tools", "tests", "src")) { return "module:$top" }
    return "module:root"
}

function Get-FunctionAtLine {
    param([object[]]$Ranges, [int]$Line)
    foreach ($range in $Ranges) {
        if ($Line -ge $range.line -and $Line -le $range.end_line) { return $range }
    }
    return $null
}

function Get-ParameterTypes {
    param([string]$Parameters)
    $result = @{}
    foreach ($match in [regex]::Matches($Parameters, "(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?<type>[A-Za-z_][A-Za-z0-9_\.]*)")) {
        $result[$match.Groups["name"].Value] = $match.Groups["type"].Value
    }
    return $result
}

function Get-UniqueQualifiedSymbol {
    param([hashtable]$SymbolMap, [string]$Base, [int]$Line)
    if (-not $SymbolMap.ContainsKey($Base)) { return $Base }
    if ($SymbolMap[$Base]) { $SymbolMap[$Base] = $null }
    return "$Base@$Line"
}

function Add-Relation {
    param(
        [System.Collections.Generic.List[object]]$List,
        [hashtable]$Seen,
        [string]$From,
        [string]$To,
        [string]$Type,
        [string]$Status,
        [object]$Evidence,
        [string]$Resolver,
        [string]$UnresolvedText = ""
    )
    if ([string]::IsNullOrEmpty($From)) { return }
    $key = "$From|$To|$Type|$($Evidence.path)|$($Evidence.start_line)|$($Evidence.symbol)"
    if ($Seen.ContainsKey($key)) { return }
    $Seen[$key] = $true
    $record = [ordered]@{
        id = ""
        from = $From
        to = $(if ([string]::IsNullOrEmpty($To)) { $null } else { $To })
        type = $Type
        status = $Status
        evidence = @($Evidence)
        resolver = $Resolver
    }
    if (-not [string]::IsNullOrEmpty($UnresolvedText)) { $record.unresolved_text = $UnresolvedText }
    $List.Add($record)
}

function Ensure-ExternalEntity {
    param(
        [hashtable]$ExternalByKey,
        [System.Collections.Generic.List[object]]$Entities,
        [string]$Key,
        [string]$Name,
        [string]$Repository,
        [string]$Path = "",
        [string]$Commit = "",
        [int]$LineStart = 0,
        [int]$LineEnd = 0
    )
    if ($ExternalByKey.ContainsKey($Key)) { return $ExternalByKey[$Key] }
    $id = "external:$Key"
    $entity = [ordered]@{
        id = $id
        kind = "external-evidence"
        name = $Name
        path = $(if ([string]::IsNullOrEmpty($Path)) { $null } else { $Path })
        repository = $Repository
        commit = $Commit
        line_start = $null
        line_end = $null
        summary = "External citation; source text is intentionally not embedded."
        aliases = @($Name, $Repository)
        evidence = @()
    }
    if ($LineStart -gt 0) {
        $entity.line_start = $LineStart
        $entity.line_end = $(if ($LineEnd -ge $LineStart) { $LineEnd } else { $LineStart })
    }
    $Entities.Add($entity)
    $ExternalByKey[$Key] = $id
    return $id
}

function Get-SourceSnippet {
    param([object]$File, [int]$StartLine, [int]$EndLine, [int]$Limit = 2200)
    $start = [Math]::Max(1, $StartLine)
    $end = [Math]::Min($File.lines.Count, [Math]::Max($start, $EndLine))
    $snippet = (($File.lines[($start - 1)..($end - 1)]) -join [Environment]::NewLine)
    if ($snippet.Length -gt $Limit) { return $snippet.Substring(0, $Limit) + "..." }
    return $snippet
}

function Get-InputFingerprint {
    param([string[]]$Paths, [hashtable]$FileByPath)
    $parts = [IO.MemoryStream]::new()
    try {
        foreach ($path in ($Paths | Sort-Object)) {
            $pathBytes = [Text.Encoding]::UTF8.GetBytes($path)
            $parts.Write($pathBytes, 0, $pathBytes.Length)
            $parts.WriteByte(0)
            $contentBytes = [IO.File]::ReadAllBytes((Join-Path $repoRoot ($path -replace "/", "\")))
            $parts.Write($contentBytes, 0, $contentBytes.Length)
            $parts.WriteByte(10)
        }
        return Get-Sha256Bytes $parts.ToArray()
    } finally {
        $parts.Dispose()
    }
}

function Get-ModuleFingerprints {
    param([string[]]$Paths)
    $result = [ordered]@{}
    $groups = [ordered]@{}
    foreach ($path in $Paths) {
        $top = if ($path -match "^src/([^/]+)") { "src/$($Matches[1])" }
            elseif ($path -match "^contracts/([^/]+)") { "contracts/$($Matches[1])" }
            elseif ($path -match "^docs/([^/]+)") { "docs/$($Matches[1])" }
            elseif ($path -match "^tests/([^/]+)") { "tests/$($Matches[1])" }
            elseif ($path -match "^tools/([^/]+)") { "tools/$($Matches[1])" }
            elseif ($path -match "^\.github/") { ".github" }
            else { $path }
        if (-not $groups.Contains($top)) { $groups[$top] = [System.Collections.Generic.List[string]]::new() }
        $groups[$top].Add($path)
    }
    foreach ($key in ($groups.Keys | Sort-Object)) {
        $groupPaths = @($groups[$key] | Sort-Object)
        $result[$key] = [ordered]@{
            tracked_file_count = $groupPaths.Count
            sha256 = Get-InputFingerprint $groupPaths @{}
        }
    }
    return $result
}

function Get-SourceSpanForCatalogTrigger {
    param([object]$Trigger, [hashtable]$FileByPath, [string]$Commit)
    $path = ([string]$Trigger.path) -replace "^res://", ""
    if ($FileByPath.ContainsKey($path)) {
        $file = $FileByPath[$path]
        $symbol = [string]$Trigger.symbol
        for ($line = 0; $line -lt $file.lines.Count; $line++) {
            if ($file.lines[$line].IndexOf($symbol, [StringComparison]::Ordinal) -ge 0) {
                return Get-SourceSpan $file ($line + 1) $symbol ($line + 1) 0 0 $Commit
            }
        }
        return Get-SourceSpan $file 1 $symbol 1 0 0 $Commit
    }
    return $null
}

function Test-Span {
    param([object]$Span, [hashtable]$FileByPath, [string]$Commit, [string]$Context)
    if (-not $Span.path -or -not $Span.file_sha256 -or -not $Span.commit) { throw "Incomplete source span: $Context" }
    if ([string]$Span.commit -ne $Commit) { throw "Source span commit mismatch: $Context" }
    if (-not $FileByPath.ContainsKey([string]$Span.path)) { throw "Source span path is not indexed: $Context -> $($Span.path)" }
    $file = $FileByPath[[string]$Span.path]
    if ([string]$Span.file_sha256 -ne [string]$file.sha256) { throw "Source span hash mismatch: $Context" }
    $start = [int]$Span.start_line
    $end = [int]$Span.end_line
    if ($start -lt 1 -or $end -lt $start -or $end -gt [int]$file.line_count) { throw "Source span line range is outside file: $Context" }
    $startText = [string]$file.lines[$start - 1]
    $endText = [string]$file.lines[$end - 1]
    if ([int]$Span.start_column -lt 1 -or [int]$Span.start_column -gt $startText.Length + 1) { throw "Source span start column is outside line: $Context" }
    if ([int]$Span.end_column -lt 1 -or [int]$Span.end_column -gt $endText.Length + 1) { throw "Source span end column is outside line: $Context" }
    $symbol = [string]$Span.symbol
    if ($symbol -and $symbol -notmatch "^(file|scope):" ) {
        $spanText = (($file.lines[($start - 1)..($end - 1)]) -join "`n")
        if ($spanText.IndexOf($symbol, [StringComparison]::Ordinal) -lt 0) { throw "Source span symbol is not present: $Context -> $symbol" }
    }
}

function Test-Model {
    param([hashtable]$Model, [hashtable]$FileByPath, [string]$Commit)
    $entityIds = @{}
    $relationIds = @{}
    foreach ($entity in $Model.entities) {
        if ($entityIds.ContainsKey($entity.id)) { throw "Duplicate entity id: $($entity.id)" }
        $entityIds[$entity.id] = $true
        foreach ($span in @($entity.evidence)) { Test-Span $span $FileByPath $Commit "entity $($entity.id)" }
    }
    foreach ($relation in $Model.relations) {
        if ([string]::IsNullOrEmpty([string]$relation.id)) { throw "Relation lacks stable id" }
        if ($relationIds.ContainsKey($relation.id)) { throw "Duplicate relation id: $($relation.id)" }
        $relationIds[$relation.id] = $true
        if (-not $entityIds.ContainsKey($relation.from)) { throw "Relation source missing: $($relation.from)" }
        if ($relation.status -in @("resolved", "external") -and ([string]::IsNullOrEmpty([string]$relation.to) -or -not $entityIds.ContainsKey($relation.to))) {
            throw "Resolved relation target missing: $($relation.id)"
        }
        if ($relation.status -eq "unknown" -and -not [string]::IsNullOrEmpty([string]$relation.to)) {
            throw "Unknown relation must not have a target: $($relation.id)"
        }
        if ($relation.evidence.Count -eq 0) { throw "Relation lacks evidence: $($relation.id)" }
        foreach ($span in @($relation.evidence)) { Test-Span $span $FileByPath $Commit "relation $($relation.id)" }
    }
    foreach ($flow in $Model.flows) {
        foreach ($span in @($flow.trigger.evidence)) { if ($span) { Test-Span $span $FileByPath $Commit "flow $($flow.id) trigger" } }
        foreach ($step in $flow.steps) {
            if (-not $entityIds.ContainsKey($step.entity_id)) { throw "Flow step missing: $($flow.id) -> $($step.entity_id)" }
            foreach ($span in @($step.evidence)) { Test-Span $span $FileByPath $Commit "flow $($flow.id) step $($step.entity_id)" }
        }
    }
    foreach ($file in $Model.files) {
        $fullPath = Join-Path $repoRoot ($file.path -replace "/", "\")
        $actualBytes = [IO.File]::ReadAllBytes($fullPath)
        $actual = Get-Sha256Bytes $actualBytes
        $embeddedFile = $FileByPath[[string]$file.path]
        if ($null -eq $embeddedFile) { throw "Embedded file record is missing: $($file.path)" }
        $embeddedBytes = [Text.UTF8Encoding]::new($false).GetBytes([string]$embeddedFile.content)
        if ($actual -ne $file.sha256) { throw "Embedded file hash mismatch: $($file.path) (actual=$actual recorded=$($file.sha256))" }
        $embeddedHash = Get-Sha256Bytes $embeddedBytes
        if ($embeddedHash -ne $actual) { throw "Embedded file content/hash mismatch: $($file.path) (embedded=$embeddedHash actual=$actual)" }
    }
}

function Test-WrittenArtifacts {
    param([string]$Root)
    foreach ($name in $generatedNames) {
        $path = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing generated artifact: $name" }
    }
    $intelligence = Read-Utf8Text (Join-Path $Root "intelligence.json") | ConvertFrom-Json
    $overview = Read-Utf8Text (Join-Path $Root "codemap.json") | ConvertFrom-Json
    $lock = Read-Utf8Text (Join-Path $Root "codemap.lock") | ConvertFrom-Json
    $currentCommit = (git -C $repoRoot rev-parse HEAD).Trim()
    $snapshotCommit = [string]$lock.current_commit
    if ([string]::IsNullOrWhiteSpace($snapshotCommit)) { throw "Lock source snapshot commit is missing" }
    $currentDirty = Get-WorkingTreeHasUncommittedChanges
    if ([bool]$lock.working_tree_has_uncommitted_changes -ne $currentDirty) { throw "Lock working-tree state is stale" }
    $inputPaths = Get-InputPaths
    if ($currentDirty) {
        if ($snapshotCommit -ne $currentCommit) { throw "Dirty source snapshot must name the current HEAD commit" }
    } elseif (-not (Test-CommitsHaveSameIndexedInputs $snapshotCommit $currentCommit $inputPaths)) {
        throw "Lock source snapshot commit does not contain the current indexed inputs"
    }
    if ([string]$lock.input_fingerprint -ne (Get-InputFingerprint $inputPaths @{})) { throw "Lock input fingerprint is stale" }
    $computedModules = Get-ModuleFingerprints $inputPaths
    if ((Get-CanonicalJson $computedModules) -ne (Get-CanonicalJson $lock.module_fingerprints)) { throw "Lock module fingerprints are stale" }
    if ($intelligence.schema_version -ne 1) { throw "Unsupported intelligence schema" }
    if ($overview.nodes.Count -gt 20) { throw "Overview has more than 20 nodes" }
    if (($overview.flows | Where-Object { $_.primary -eq $true }).Count -gt 5) { throw "Overview has more than five primary flows" }
    if ([string]$overview.generated_from_commit -ne $snapshotCommit) { throw "Overview source snapshot commit is stale" }
    if ([string]$intelligence.repository.commit -ne $snapshotCommit) { throw "Intelligence source snapshot commit is stale" }
    if ([string]$overview.generated_at -ne [string]$intelligence.repository.generated_at -or [string]$overview.generated_at -ne [string]$lock.generated_at) { throw "Generated timestamps do not match" }
    $artifactFileByPath = @{}
    foreach ($file in $intelligence.files) {
        $artifactFileByPath[[string]$file.path] = [ordered]@{path=$file.path;sha256=$file.sha256;line_count=$file.line_count;content=$file.content;lines=[regex]::Split([string]$file.content,"\r\n|\n|\r")}
    }
    Test-Model ([ordered]@{files=$intelligence.files;entities=$intelligence.entities;relations=$intelligence.relations;flows=$intelligence.flows}) $artifactFileByPath $snapshotCommit
    $ids = @{}
    foreach ($entity in $intelligence.entities) { $ids[$entity.id] = $true }
    foreach ($relation in $intelligence.relations) {
        if (-not $ids.ContainsKey($relation.from)) { throw "Artifact relation source missing: $($relation.from)" }
        if ($relation.status -in @("resolved", "external") -and -not $ids.ContainsKey($relation.to)) { throw "Artifact relation target missing: $($relation.to)" }
    }
    $overviewIds = @{}
    foreach ($node in $overview.nodes) {
        if ($overviewIds.ContainsKey($node.id)) { throw "Duplicate overview node: $($node.id)" }
        $overviewIds[$node.id] = $true
        foreach ($evidence in @($node.evidence)) {
            if (-not $artifactFileByPath.ContainsKey($evidence.path)) { throw "Overview node evidence path missing: $($node.id) -> $($evidence.path)" }
            if ($evidence.symbol -and $evidence.symbol -notmatch "^(file|scope):" -and ([string]$artifactFileByPath[$evidence.path].content).IndexOf([string]$evidence.symbol,[StringComparison]::Ordinal) -lt 0) { throw "Overview node evidence symbol missing: $($node.id) -> $($evidence.symbol)" }
        }
    }
    $allowedOverviewTypes = @("imports", "calls", "reads", "writes", "publishes", "subscribes")
    foreach ($edge in $overview.edges) {
        if (-not $overviewIds.ContainsKey($edge.from) -or -not $overviewIds.ContainsKey($edge.to)) { throw "Overview edge references a missing node" }
        if ($allowedOverviewTypes -notcontains [string]$edge.type) { throw "Unsupported overview edge type: $($edge.type)" }
        foreach ($evidence in @($edge.evidence)) {
            if (-not $artifactFileByPath.ContainsKey($evidence.path)) { throw "Overview edge evidence path missing: $($edge.from) -> $($evidence.to)" }
            if ($evidence.symbol -and ([string]$artifactFileByPath[$evidence.path].content).IndexOf([string]$evidence.symbol,[StringComparison]::Ordinal) -lt 0) { throw "Overview edge evidence symbol missing: $($evidence.symbol)" }
        }
    }
    foreach ($flow in $overview.flows) {
        foreach ($step in @($flow.steps)) { if (-not $overviewIds.ContainsKey([string]$step)) { throw "Overview flow step missing: $step" } }
        if (-not $artifactFileByPath.ContainsKey($flow.trigger.path)) { throw "Overview flow trigger path missing: $($flow.trigger.path)" }
        if ($flow.trigger.symbol -and ([string]$artifactFileByPath[$flow.trigger.path].content).IndexOf([string]$flow.trigger.symbol,[StringComparison]::Ordinal) -lt 0) { throw "Overview flow trigger symbol missing: $($flow.trigger.symbol)" }
    }
    $chunkLines = @((Read-Utf8Text (Join-Path $Root "chunks.jsonl")) -split "\r\n|\n|\r" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($line in $chunkLines) {
        $chunk = $line | ConvertFrom-Json
        if (-not $ids.ContainsKey($chunk.entity_id)) { throw "Chunk entity missing: $($chunk.entity_id)" }
        if (-not $artifactFileByPath.ContainsKey($chunk.path)) { throw "Chunk source path missing: $($chunk.path)" }
        $file = $artifactFileByPath[$chunk.path]
        if ([string]$chunk.source_sha256 -ne [string]$file.sha256 -or [string]$chunk.commit -ne $snapshotCommit) { throw "Chunk source provenance mismatch: $($chunk.id)" }
        $start = [int]$chunk.start_line; $end = [int]$chunk.end_line
        if ($start -lt 1 -or $end -lt $start -or $end -gt [int]$file.line_count) { throw "Chunk line range is outside file: $($chunk.id)" }
        $actualChunk = (($file.lines[($start - 1)..($end - 1)]) -join [Environment]::NewLine)
        if ([string]$chunk.text -ne $actualChunk -and -not ([string]$chunk.text.EndsWith("...") -and $actualChunk.StartsWith(([string]$chunk.text).Substring(0,([string]$chunk.text).Length - 3),[StringComparison]::Ordinal))) { throw "Chunk text mismatch: $($chunk.id)" }
    }
    $html = Read-Utf8Text (Join-Path $Root "codemap.html")
    if ($html -match "<script[^>]+src=|<link[^>]+href=") { throw "HTML contains an external asset reference" }
    if ($html -notmatch "const OVERVIEW = ") { throw "HTML overview payload missing" }
    if ($html -notmatch "const INTELLIGENCE = ") { throw "HTML intelligence payload missing" }
    $overviewPayloadMatch = [regex]::Match($html, "const OVERVIEW = (?<payload>\{.*?\});\r?\nconst INTELLIGENCE = ", [Text.RegularExpressions.RegexOptions]::Singleline)
    $intelligencePayloadMatch = [regex]::Match($html, "const INTELLIGENCE = (?<payload>\{.*?\});\r?\nconst entities =", [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $overviewPayloadMatch.Success -or -not $intelligencePayloadMatch.Success) { throw "HTML embedded payload boundaries are invalid" }
    $embeddedOverview = $overviewPayloadMatch.Groups["payload"].Value | ConvertFrom-Json
    $embeddedIntelligence = $intelligencePayloadMatch.Groups["payload"].Value | ConvertFrom-Json
    if ((Get-CanonicalJson $embeddedOverview) -ne (Get-CanonicalJson $overview)) { throw "HTML overview payload differs from codemap.json" }
    if ((Get-CanonicalJson $embeddedIntelligence) -ne (Get-CanonicalJson $intelligence)) { throw "HTML intelligence payload differs from intelligence.json" }
    foreach ($name in @("codemap.html", "codemap.json", "intelligence.json", "chunks.jsonl")) {
        $hash = Get-Sha256Bytes ([IO.File]::ReadAllBytes((Join-Path $Root $name)))
        $expectedHash = $lock.output_hashes.PSObject.Properties[$name].Value
        if (-not $expectedHash -or $expectedHash -ne $hash) { throw "Output hash mismatch: $name" }
    }
    Write-Host ("Source intelligence validated: {0} entities, {1} relations, {2} flows, {3} chunks." -f $intelligence.entities.Count, $intelligence.relations.Count, $intelligence.flows.Count, $chunkLines.Count)
}

if ($ValidateOnly) {
    Test-WrittenArtifacts $outputRoot
    exit 0
}

$catalog = Get-Content -Raw $catalogPath | ConvertFrom-Json
$inputPaths = Get-InputPaths
$commit = (git -C $repoRoot rev-parse HEAD).Trim()
$dirtyBefore = Get-WorkingTreeHasUncommittedChanges
$oldLock = $null
if (Test-Path -LiteralPath (Join-Path $outputRoot "codemap.lock")) {
    try { $oldLock = Get-Content -Raw (Join-Path $outputRoot "codemap.lock") | ConvertFrom-Json } catch { $oldLock = $null }
}
$fileByPath = @{}
foreach ($path in $inputPaths) {
    $record = Get-TextFileRecord $path $commit
    $fileByPath[$path] = $record
}
$inputFingerprint = Get-InputFingerprint $inputPaths $fileByPath
if ($oldLock -and $oldLock.generator_version -eq $generatorVersion -and [string]$oldLock.input_fingerprint -eq $inputFingerprint -and -not $dirtyBefore) {
    $oldSnapshotCommit = [string]$oldLock.current_commit
    if (Test-CommitsHaveSameIndexedInputs $oldSnapshotCommit $commit $inputPaths) {
        $commit = $oldSnapshotCommit
    }
}
$effectiveGeneratedAt = Get-CanonicalGeneratedAt $GeneratedAt
if ([string]::IsNullOrWhiteSpace($effectiveGeneratedAt) -and $oldLock -and $oldLock.input_fingerprint -eq $inputFingerprint -and $oldLock.generator_version -eq $generatorVersion) {
    $effectiveGeneratedAt = Get-CanonicalGeneratedAt $oldLock.generated_at
}
if ([string]::IsNullOrWhiteSpace($effectiveGeneratedAt)) {
    $effectiveGeneratedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

$entities = [System.Collections.Generic.List[object]]::new()
$relations = [System.Collections.Generic.List[object]]::new()
$relationSeen = @{}
$entityById = @{}
$moduleEntities = @{}
$externalByKey = @{}
$functionRangesByFile = @{}
$symbolByQualified = @{}
$symbolsBySimple = @{}
$propertyByQualified = @{}
$fileRecords = @()
$diagnostics = [System.Collections.Generic.List[object]]::new()
$externalReferences = @{}
$referenceLockPath = Join-Path $repoRoot "docs\references.lock.json"
if (Test-Path -LiteralPath $referenceLockPath) {
    try {
        $referenceLock = Get-Content -Raw $referenceLockPath | ConvertFrom-Json
        foreach ($reference in @($referenceLock.references)) {
            $externalReferences[[string]$reference.id] = $reference
        }
    } catch {
        throw "Unable to parse external reference lock: $($_.Exception.Message)"
    }
}
foreach ($requiredReferenceId in @("realmz-castle-oracle", "providence-compiler-base")) {
    if (-not $externalReferences.ContainsKey($requiredReferenceId)) {
        throw "Required external reference is missing from docs/references.lock.json: $requiredReferenceId"
    }
}

foreach ($node in $catalog.overview_nodes) {
    $moduleId = "module:$($node.id)"
    $entity = [ordered]@{
        id = $moduleId
        kind = "module"
        name = [string]$node.id
        path = [string]$node.path
        role = [string]$node.role
        summary = [string]$node.role
        boundary = [string]$node.boundary
        aliases = @([string]$node.id, [string]$node.role)
        evidence = @((Get-CatalogSpan $commit ([string]$node.id)))
    }
    $entities.Add($entity)
    $entityById[$moduleId] = $entity
    $moduleEntities[$moduleId] = $entity
}

foreach ($concept in $catalog.concept_aliases.PSObject.Properties) {
    $conceptId = "concept:$($concept.Name)"
    $aliases = @($concept.Value | ForEach-Object { [string]$_ })
    $entity = [ordered]@{
        id = $conceptId
        kind = "concept"
        name = [string]$concept.Name
        path = "tools/source-intelligence/catalog.json"
        summary = "Authored concept aliases: $($aliases -join ", ")"
        aliases = @([string]$concept.Name) + $aliases
        evidence = @((Get-CatalogSpan $commit ([string]$concept.Name)))
    }
    $entities.Add($entity)
    $entityById[$conceptId] = $entity
}

foreach ($path in $inputPaths) {
    $file = $fileByPath[$path]
    $moduleId = Get-ModuleIdForPath $path $catalog.overview_nodes
    $doxId = Get-NearestDoxId $path $fileByPath
    $file.module_id = $moduleId
    $file.dox_scope_id = $doxId
    $fileRecords += [ordered]@{
        id = $file.id
        path = $file.path
        sha256 = $file.sha256
        line_count = $file.line_count
        content = $file.content
        module_id = $moduleId
        dox_scope_id = $doxId
    }
    if (-not $entityById.ContainsKey($moduleId)) {
        $topName = $moduleId.Substring("module:".Length)
        $moduleEntity = [ordered]@{
            id = $moduleId
            kind = "module"
            name = $topName
            path = $topName
            role = "Indexed source domain"
            summary = "Indexed source domain: $topName"
            boundary = "support"
            aliases = @($topName)
            evidence = @((Get-PathEvidence $file $commit "scope:$topName"))
        }
        $entities.Add($moduleEntity)
        $entityById[$moduleId] = $moduleEntity
        $moduleEntities[$moduleId] = $moduleEntity
    }
    $fileEntity = [ordered]@{
        id = $file.id
        kind = "file"
        name = [IO.Path]::GetFileName($path)
        path = $path
        summary = "Indexed source file"
        module_id = $moduleId
        dox_scope_id = $doxId
        aliases = @($path)
        evidence = @((Get-PathEvidence $file $commit "file:$path"))
    }
    $entities.Add($fileEntity)
    $entityById[$file.id] = $fileEntity
    Add-Relation $relations $relationSeen $moduleId $file.id "contains" "resolved" (Get-PathEvidence $file $commit "file:$path") "filesystem-scope"
    if ($doxId) {
        Add-Relation $relations $relationSeen $doxId $file.id "governs" "resolved" (Get-PathEvidence $file $commit "scope:$path") "nearest-AGENTS"
    }
}

foreach ($path in $inputPaths | Where-Object { $_.ToLowerInvariant().EndsWith(".md") }) {
    $file = $fileByPath[$path]
    $headings = @()
    for ($i = 0; $i -lt $file.lines.Count; $i++) {
        $match = [regex]::Match([string]$file.lines[$i], "^(?<level>#{1,6})\s+(?<title>.+?)\s*$")
        if ($match.Success) { $headings += [ordered]@{ line = $i + 1; level = $match.Groups["level"].Value.Length; title = $match.Groups["title"].Value } }
    }
    $usedSlugs = @{}
    for ($i = 0; $i -lt $headings.Count; $i++) {
        $heading = $headings[$i]
        $slug = New-Slug $heading.title
        if ($usedSlugs.ContainsKey($slug)) { $usedSlugs[$slug]++; $slug = "$slug-$($usedSlugs[$slug])" } else { $usedSlugs[$slug] = 1 }
        $endLine = if ($i + 1 -lt $headings.Count) { $headings[$i + 1].line - 1 } else { $file.lines.Count }
        $kind = if ($path -eq "AGENTS.md" -or $path.EndsWith("/AGENTS.md")) { "dox-section" } else { "doc-section" }
        $entityId = "doc:$path#$slug"
        $sectionText = Get-SourceSnippet $file $heading.line $endLine 5000
        $span = Get-SourceSpan $file $heading.line $heading.title $endLine 0 0 $commit $(if($kind -eq "dox-section"){"dox"}else{"documentation"})
        $entity = [ordered]@{
            id = $entityId
            kind = $kind
            name = [string]$heading.title
            path = $path
            summary = $sectionText.Substring(0, [Math]::Min(700, $sectionText.Length))
            module_id = $file.module_id
            dox_scope_id = $(if ($kind -eq "dox-section") { "dox:$path" } else { $file.dox_scope_id })
            aliases = @($heading.title, (New-Slug $heading.title))
            span = $span
            evidence = @($span)
        }
        $entities.Add($entity); $entityById[$entityId] = $entity
        if ($kind -eq "dox-section" -and $i -eq 0) {
            $doxEntity = [ordered]@{id="dox:$path";kind="dox";name=$path;path=$path;summary="Inherited DOX contract for this source scope.";module_id=$file.module_id;aliases=@($path,"DOX","AGENTS");evidence=@($span)}
            if (-not $entityById.ContainsKey($doxEntity.id)) { $entities.Add($doxEntity); $entityById[$doxEntity.id] = $doxEntity }
        }
    }
}

foreach ($path in $inputPaths | Where-Object { $_.ToLowerInvariant().EndsWith(".gd") }) {
    $file = $fileByPath[$path]
    $classMatch = $null
    foreach ($rawLine in $file.lines) {
        $candidate = [regex]::Match([string]$rawLine, "^\s*class_name\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)")
        if ($candidate.Success) { $classMatch = $candidate; break }
    }
    $className = if ($classMatch -and $classMatch.Success) { $classMatch.Groups["name"].Value } else { [IO.Path]::GetFileNameWithoutExtension($path) }
    $ranges = [System.Collections.Generic.List[object]]::new()
    $declarations = [System.Collections.Generic.List[object]]::new()
    for ($lineIndex = 0; $lineIndex -lt $file.lines.Count; $lineIndex++) {
        $line = [string]$file.lines[$lineIndex]; $lineNumber = $lineIndex + 1
        $classLine = [regex]::Match($line, "^\s*class_name\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)")
        if ($classLine.Success) {
            $symbol = $classLine.Groups["name"].Value; $qualifiedClass = Get-UniqueQualifiedSymbol $symbolByQualified $symbol $lineNumber; $id = "symbol:$path#$qualifiedClass"
            $entity = [ordered]@{id=$id;kind="class";name=$symbol;path=$path;summary="GDScript global class $symbol";module_id=$file.module_id;dox_scope_id=$file.dox_scope_id;aliases=@($symbol);evidence=@((Get-SourceSpan $file $lineNumber $symbol $lineNumber 0 0 $commit))}
            $entities.Add($entity); $entityById[$id]=$entity
            $declarations.Add([ordered]@{name=$symbol;qualified=$qualifiedClass;id=$id;kind="class";line=$lineNumber;end_line=$lineNumber;type=$symbol})
            $symbolByQualified[$qualifiedClass]=$id
            if(-not $symbolsBySimple.ContainsKey($symbol)){$symbolsBySimple[$symbol]=[System.Collections.Generic.List[string]]::new()};$symbolsBySimple[$symbol].Add($id)
        }
        $funcMatch = [regex]::Match($line, "^\s*(?:static\s+)?func\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*\((?<params>[^)]*)\)")
        if ($funcMatch.Success) {
            $name=$funcMatch.Groups["name"].Value;$baseQualified="$className.$name";$qualified=Get-UniqueQualifiedSymbol $symbolByQualified $baseQualified $lineNumber;$id="symbol:$path#$qualified";$isTest=$path -like "tests/*" -and ($name -like "_test_*" -or $name -like "test_*");$endLine=$file.lines.Count
            for($next=$lineIndex+1;$next -lt $file.lines.Count;$next++){ $candidate=[string]$file.lines[$next];if($candidate -match "^\S" -and $candidate -match "^(?:static\s+)?(?:func|signal|const|var|enum|class_name|class)\b"){$endLine=$next;break} }
            $span=Get-SourceSpan $file $lineNumber $name $endLine 0 0 $commit
            $entity=[ordered]@{id=$id;kind=$(if($isTest){"test"}else{"function"});name=$qualified;path=$path;summary="GDScript function $qualified";module_id=$file.module_id;dox_scope_id=$file.dox_scope_id;aliases=@($name,$qualified);span=$span;evidence=@($span)}
            $entities.Add($entity);$entityById[$id]=$entity
            $declaration=[ordered]@{name=$name;qualified=$qualified;id=$id;kind=$entity.kind;line=$lineNumber;end_line=$endLine;params=$funcMatch.Groups["params"].Value;param_types=Get-ParameterTypes $funcMatch.Groups["params"].Value;type=$className}
            $declarations.Add($declaration);$ranges.Add($declaration);$symbolByQualified[$qualified]=$id
            if(-not $symbolsBySimple.ContainsKey($name)){$symbolsBySimple[$name]=[System.Collections.Generic.List[string]]::new()};$symbolsBySimple[$name].Add($id)
        }
        $signalMatch=[regex]::Match($line,"^\S*signal\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)")
        if($signalMatch.Success){
            $name=$signalMatch.Groups["name"].Value;$baseQualified="$className.$name";$qualified=Get-UniqueQualifiedSymbol $symbolByQualified $baseQualified $lineNumber;$id="symbol:$path#$qualified";$span=Get-SourceSpan $file $lineNumber $name $lineNumber 0 0 $commit
            $entity=[ordered]@{id=$id;kind="signal";name=$qualified;path=$path;summary="GDScript signal $qualified";module_id=$file.module_id;dox_scope_id=$file.dox_scope_id;aliases=@($name,$qualified);evidence=@($span)};$entities.Add($entity);$entityById[$id]=$entity;$declarations.Add([ordered]@{name=$name;qualified=$qualified;id=$id;kind="signal";line=$lineNumber;end_line=$lineNumber;type=$className});$symbolByQualified[$qualified]=$id;if(-not $symbolsBySimple.ContainsKey($name)){$symbolsBySimple[$name]=[System.Collections.Generic.List[string]]::new()};$symbolsBySimple[$name].Add($id)
        }
        $propertyMatch=[regex]::Match($line,"^\s*(?:static\s+)?(?:const|var)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(?<type>[A-Za-z_][A-Za-z0-9_\.]*))?")
        if($line -match "^\S" -and $propertyMatch.Success){
            $name=$propertyMatch.Groups["name"].Value;$baseQualified="$className.$name";$qualified=Get-UniqueQualifiedSymbol $symbolByQualified $baseQualified $lineNumber;$id="symbol:$path#$qualified";$span=Get-SourceSpan $file $lineNumber $name $lineNumber 0 0 $commit
            $entity=[ordered]@{id=$id;kind="property";name=$qualified;path=$path;summary="GDScript property $qualified";module_id=$file.module_id;dox_scope_id=$file.dox_scope_id;aliases=@($name,$qualified);evidence=@($span)};$entities.Add($entity);$entityById[$id]=$entity;$declarations.Add([ordered]@{name=$name;qualified=$qualified;id=$id;kind="property";line=$lineNumber;end_line=$lineNumber;type=$(if($propertyMatch.Groups["type"].Success){$propertyMatch.Groups["type"].Value}else{""})});$propertyByQualified[$qualified]=$id;$symbolByQualified[$qualified]=$id
        }
        $enumMatch=[regex]::Match($line,"^\s*enum\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)")
        if($line -match "^\S" -and $enumMatch.Success){
            $name=$enumMatch.Groups["name"].Value;$baseQualified="$className.$name";$qualified=Get-UniqueQualifiedSymbol $symbolByQualified $baseQualified $lineNumber;$id="symbol:$path#$qualified";$span=Get-SourceSpan $file $lineNumber $name $lineNumber 0 0 $commit;$entity=[ordered]@{id=$id;kind="enum";name=$qualified;path=$path;summary="GDScript enum $qualified";module_id=$file.module_id;dox_scope_id=$file.dox_scope_id;aliases=@($name,$qualified);evidence=@($span)};$entities.Add($entity);$entityById[$id]=$entity;$declarations.Add([ordered]@{name=$name;qualified=$qualified;id=$id;kind="enum";line=$lineNumber;end_line=$lineNumber;type=$className});$symbolByQualified[$qualified]=$id
        }
    }
    $functionRangesByFile[$path]=@($ranges)
    Add-Relation $relations $relationSeen $file.module_id $file.id "declares" "resolved" (Get-PathEvidence $file $commit "file:$path") "file-index"
    foreach($declaration in $declarations){Add-Relation $relations $relationSeen $file.id $declaration.id "declares" "resolved" (Get-SourceSpan $file $declaration.line $declaration.name $declaration.end_line 0 0 $commit) "declaration"}
}

$ignoredCalls=@("if","for","while","match","return","await","assert","print","push_error","push_warning","preload","load","super","new","str","int","float","bool","len","typeof","range","min","max","abs","clamp","String","StringName","Vector2","Vector3","Color","Array","Dictionary")
foreach($path in $inputPaths|Where-Object{$_.ToLowerInvariant().EndsWith(".gd")}){
    $file=$fileByPath[$path];$ranges=@($functionRangesByFile[$path]);$className=$null
    foreach($rawLine in $file.lines){$cm=[regex]::Match([string]$rawLine,"^\s*class_name\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)");if($cm.Success){$className=$cm.Groups["name"].Value;break}}
    if(-not $className){$className=[IO.Path]::GetFileNameWithoutExtension($path)}
    $fileTypeMap=@{}
    for($lineIndex=0;$lineIndex -lt $file.lines.Count;$lineIndex++){
        $line=[string]$file.lines[$lineIndex];$lineNumber=$lineIndex+1;$range=Get-FunctionAtLine $ranges $lineNumber;$fromId=$(if($range){$range.id}else{"file:$path"})
        foreach($binding in [regex]::Matches($line,"(?:var|const)\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?<type>[A-Za-z_][A-Za-z0-9_\.]*)")){$fileTypeMap[$binding.Groups["name"].Value]=$binding.Groups["type"].Value}
        foreach($load in [regex]::Matches($line,"\b(?<kind>preload|load)\s*\(\s*['""]res://(?<path>[^'""]+)['""]")){
            $target=($load.Groups["path"].Value -replace "\\","/").TrimEnd(".",",",")",";");$ev=Get-SourceSpan $file $lineNumber $load.Value $lineNumber 0 0 $commit
            if($fileByPath.ContainsKey($target)){Add-Relation $relations $relationSeen $fromId "file:$target" "imports" "resolved" $ev $load.Groups["kind"].Value}else{Add-Relation $relations $relationSeen $fromId "" "imports" "unknown" $ev $load.Groups["kind"].Value $target}
        }
        foreach($ctor in [regex]::Matches($line,"\b(?<class>[A-Z][A-Za-z0-9_]*)\.new\s*\(")){
            $class=$ctor.Groups["class"].Value;$ev=Get-SourceSpan $file $lineNumber $ctor.Value $lineNumber 0 0 $commit
            if($symbolByQualified.ContainsKey($class)){Add-Relation $relations $relationSeen $fromId $symbolByQualified[$class] "constructs" "resolved" $ev "global-class"}else{$external=Ensure-ExternalEntity $externalByKey $entities "godot:$class" $class "Godot";Add-Relation $relations $relationSeen $fromId $external "constructs" "external" $ev "external-type"}
        }
        foreach($staticCall in [regex]::Matches($line,"\b(?<class>[A-Z][A-Za-z0-9_]*)\.(?<method>[a-z_][A-Za-z0-9_]*)\s*\(")){
            $class=$staticCall.Groups["class"].Value;$method=$staticCall.Groups["method"].Value;$qualified="$class.$method";$ev=Get-SourceSpan $file $lineNumber $staticCall.Value $lineNumber 0 0 $commit
            if($symbolByQualified.ContainsKey($qualified) -and $symbolByQualified[$qualified]){Add-Relation $relations $relationSeen $fromId $symbolByQualified[$qualified] "calls" "resolved" $ev "qualified-symbol"}elseif($ignoredCalls -notcontains $method){$external=Ensure-ExternalEntity $externalByKey $entities "godot:$class.$method" $qualified "Godot";Add-Relation $relations $relationSeen $fromId $external "calls" "external" $ev "external-type"}
        }
        foreach($memberCall in [regex]::Matches($line,"(?<![A-Za-z0-9_])(?<receiver>[A-Za-z_][A-Za-z0-9_]*)\.(?<method>[a-z_][A-Za-z0-9_]*)\s*\(")){
            $receiver=$memberCall.Groups["receiver"].Value;$method=$memberCall.Groups["method"].Value;if($receiver -in @("self","super")){continue};$type=$(if($fileTypeMap.ContainsKey($receiver)){$fileTypeMap[$receiver]}else{""});$ev=Get-SourceSpan $file $lineNumber $memberCall.Value $lineNumber 0 0 $commit;$qualified=$(if($type){"$type.$method"}else{""})
            if($qualified -and $symbolByQualified.ContainsKey($qualified)){Add-Relation $relations $relationSeen $fromId $symbolByQualified[$qualified] "calls" "resolved" $ev "typed-receiver"}elseif($type){$external=Ensure-ExternalEntity $externalByKey $entities "type:$qualified" $qualified "external-type";Add-Relation $relations $relationSeen $fromId $external "calls" "external" $ev "typed-external"}elseif($method -notin @("connect","emit")){Add-Relation $relations $relationSeen $fromId "" "calls" "unknown" $ev "untyped-receiver" $memberCall.Value}
        }
        foreach($call in [regex]::Matches($line,"(?<![A-Za-z0-9_\.])(?<name>[a-z_][A-Za-z0-9_]*)\s*\(")){
            $name=$call.Groups["name"].Value;if($ignoredCalls -contains $name){continue};$ev=Get-SourceSpan $file $lineNumber $call.Value $lineNumber 0 0 $commit
            if($symbolByQualified.ContainsKey("$className.$name") -and $symbolByQualified["$className.$name"]){Add-Relation $relations $relationSeen $fromId $symbolByQualified["$className.$name"] "calls" "resolved" $ev "local-symbol"}elseif($symbolsBySimple.ContainsKey($name) -and $symbolsBySimple[$name].Count -eq 1){Add-Relation $relations $relationSeen $fromId $symbolsBySimple[$name][0] "calls" "resolved" $ev "unique-symbol"}elseif($name -notin @("connect","emit")){Add-Relation $relations $relationSeen $fromId "" "calls" "unknown" $ev "unresolved-call" $name}
        }
        foreach($write in [regex]::Matches($line,"\b(?<receiver>[A-Za-z_][A-Za-z0-9_]*)\.(?<property>[a-z_][A-Za-z0-9_]*)\s*=")){
            $receiver=$write.Groups["receiver"].Value;$property=$write.Groups["property"].Value;$type=$(if($fileTypeMap.ContainsKey($receiver)){$fileTypeMap[$receiver]}else{""});$qualified=$(if($type){"$type.$property"}else{""});$ev=Get-SourceSpan $file $lineNumber $write.Value $lineNumber 0 0 $commit
            if($qualified -and $propertyByQualified.ContainsKey($qualified)){Add-Relation $relations $relationSeen $fromId $propertyByQualified[$qualified] "writes" "resolved" $ev "typed-property"}elseif($type){$external=Ensure-ExternalEntity $externalByKey $entities "type:$qualified" $qualified "external-type";Add-Relation $relations $relationSeen $fromId $external "writes" "external" $ev "typed-external"}else{Add-Relation $relations $relationSeen $fromId "" "writes" "unknown" $ev "untyped-property" $write.Value}
        }
        foreach($signalCall in [regex]::Matches($line,"(?<name>[A-Za-z_][A-Za-z0-9_]*)\.(?<verb>connect|emit)\s*\(")){
            $name=$signalCall.Groups["name"].Value;$verb=$signalCall.Groups["verb"].Value;$ev=Get-SourceSpan $file $lineNumber $signalCall.Value $lineNumber 0 0 $commit;$signalCandidates=@();if($symbolsBySimple.ContainsKey($name)){$signalCandidates=@($symbolsBySimple[$name]|Where-Object{$entityById[$_].kind -eq "signal"})}
            $signalType=$(if($verb -eq "connect"){"subscribes"}else{"publishes"});if($signalCandidates.Count -eq 1){Add-Relation $relations $relationSeen $fromId $signalCandidates[0] $signalType "resolved" $ev "signal"}else{Add-Relation $relations $relationSeen $fromId "" $signalType "unknown" $ev "signal" $name}
        }
        foreach($dynamic in [regex]::Matches($line,"\b(?<name>call|callv|call_deferred)\s*\(")){
            $ev=Get-SourceSpan $file $lineNumber $dynamic.Value $lineNumber 0 0 $commit;Add-Relation $relations $relationSeen $fromId "" "calls" "unknown" $ev "dynamic-dispatch" $line.Trim();$diagnostics.Add([ordered]@{kind="unknown-reference";path=$path;line=$lineNumber;message="Dynamic dispatch cannot be resolved statically.";text=$line.Trim()})
        }
    }
}

foreach($path in $inputPaths|Where-Object{$_.ToLowerInvariant().EndsWith(".md")}){
    $file=$fileByPath[$path];$docEntities=@($entities|Where-Object{$_.path -eq $path -and $_.kind -in @("doc-section","dox-section")})
    foreach($doc in $docEntities){
        $start=[int]$doc.evidence[0].start_line;$end=[int]$doc.evidence[0].end_line
        for($lineIndex=$start-1;$lineIndex -lt $end -and $lineIndex -lt $file.lines.Count;$lineIndex++){
            $line=[string]$file.lines[$lineIndex]
            foreach($citation in [regex]::Matches($line,"(?<path>(?:src|src-tauri|tests|tools|contracts|docs)/[A-Za-z0-9_./-]+)(?::(?<start>\d+)(?:-(?<end>\d+))?)?")){
                $target=($citation.Groups["path"].Value.TrimEnd(".",",",")",";",":")) -replace "\\","/";$ev=Get-SourceSpan $file ($lineIndex+1) $citation.Value ($lineIndex+1) 0 0 $commit "documentation-citation"
                $externalLineStart=0;$externalLineEnd=0
                if($citation.Groups["start"].Success){$externalLineStart=[int]$citation.Groups["start"].Value;$externalLineEnd=$(if($citation.Groups["end"].Success){[int]$citation.Groups["end"].Value}else{$externalLineStart})}
                if($target -like "src/realmz_orig/*"){
                    $reference=$externalReferences["realmz-castle-oracle"]
                    $external=Ensure-ExternalEntity $externalByKey $entities ("castle:"+$target) $target ([string]$reference.repository) $target ([string]$reference.commit) $externalLineStart $externalLineEnd
                    $externalEntity=@($entities|Where-Object{$_.id -eq $external})[0];if($externalEntity -and $externalEntity.evidence.Count -eq 0){$externalEntity.evidence=@($ev)}
                    if($externalLineStart -le 0){$diagnostics.Add([ordered]@{kind="external-citation-missing-line";path=$path;line=$lineIndex+1;message="External Castle citation has no cited source line range.";target=$target})}
                    Add-Relation $relations $relationSeen $doc.id $external "references" "external" $ev "external-citation"
                } elseif($target -like "src-tauri/*"){
                    $reference=$externalReferences["providence-compiler-base"]
                    $external=Ensure-ExternalEntity $externalByKey $entities ("providence:"+$target) $target ([string]$reference.repository) $target ([string]$reference.commit) $externalLineStart $externalLineEnd
                    $externalEntity=@($entities|Where-Object{$_.id -eq $external})[0];if($externalEntity -and $externalEntity.evidence.Count -eq 0){$externalEntity.evidence=@($ev)}
                    if($externalLineStart -le 0){$diagnostics.Add([ordered]@{kind="external-citation-missing-line";path=$path;line=$lineIndex+1;message="External Providence citation has no cited source line range.";target=$target})}
                    Add-Relation $relations $relationSeen $doc.id $external "references" "external" $ev "external-citation"
                } elseif($fileByPath.ContainsKey($target)){Add-Relation $relations $relationSeen $doc.id "file:$target" "documents" "resolved" $ev "local-citation"
                } else{Add-Relation $relations $relationSeen $doc.id "" "references" "unknown" $ev "missing-local-citation" $target;$diagnostics.Add([ordered]@{kind="unresolved-document-citation";path=$path;line=$lineIndex+1;message="Referenced path is not in the indexed scope.";target=$target})}
            }
        }
    }
}

$entityById=@{};foreach($entity in $entities){$entityById[$entity.id]=$entity}
foreach($test in @($entities|Where-Object{$_.kind -eq "test"})){
    foreach($relation in @($relations|Where-Object{$_.from -eq $test.id -and $_.status -eq "resolved" -and $_.to -like "symbol:*"})){
        Add-Relation $relations $relationSeen $test.id $relation.to "tests" "resolved" $relation.evidence[0] "test-call"
        Add-Relation $relations $relationSeen "module:tests" $relation.to "tests" "resolved" $relation.evidence[0] "test-call"
    }
}
$entityById=@{};foreach($entity in $entities){$entityById[$entity.id]=$entity}

$searchDocuments=[System.Collections.Generic.List[object]]::new();$chunks=[System.Collections.Generic.List[object]]::new();$relatedByEntity=@{}
foreach($relation in $relations){
    if($relation.from){if(-not $relatedByEntity.ContainsKey($relation.from)){$relatedByEntity[$relation.from]=[System.Collections.Generic.List[string]]::new()};if($relation.to -and -not $relatedByEntity[$relation.from].Contains($relation.to)){$relatedByEntity[$relation.from].Add($relation.to)}}
    if($relation.to){if(-not $relatedByEntity.ContainsKey($relation.to)){$relatedByEntity[$relation.to]=[System.Collections.Generic.List[string]]::new()};if($relation.from -and -not $relatedByEntity[$relation.to].Contains($relation.from)){$relatedByEntity[$relation.to].Add($relation.from)}}
}
foreach($entity in ($entities|Sort-Object id)){
    $related=@();if($relatedByEntity.ContainsKey($entity.id)){$related=@($relatedByEntity[$entity.id]|Sort-Object)}
    $searchDocuments.Add([ordered]@{id=$entity.id;kind=$entity.kind;name=$entity.name;path=$entity.path;module_id=$entity.module_id;dox_scope_id=$entity.dox_scope_id;aliases=@($entity.aliases);summary=[string]$entity.summary;related_ids=@($related)})
    if($entity.path -and $fileByPath.ContainsKey($entity.path) -and $entity.evidence.Count -gt 0){$span=$entity.evidence[0];if($span.start_line -and $span.end_line){$file=$fileByPath[$entity.path];$chunks.Add([ordered]@{id="chunk:$($entity.id)";entity_id=$entity.id;kind=$entity.kind;title=$entity.name;path=$entity.path;start_line=$span.start_line;end_line=$span.end_line;module_id=$entity.module_id;dox_scope_id=$entity.dox_scope_id;text=Get-SourceSnippet $file ([int]$span.start_line) ([int]$span.end_line) 8000;source_sha256=$file.sha256;commit=$commit})}}
}
foreach($file in $fileRecords){
    if($file.content.Length -gt 0){$lines=$file.content -split "\r\n|\n|\r";$part=0;for($start=0;$start -lt $lines.Count;$start+=160){$end=[Math]::Min($lines.Count-1,$start+159);$chunks.Add([ordered]@{id="chunk:$($file.id):$part";entity_id=$file.id;kind="file";title="$($file.path) part $part";path=$file.path;start_line=$start+1;end_line=$end+1;module_id=$file.module_id;dox_scope_id=$file.dox_scope_id;text=(($lines[$start..$end])-join [Environment]::NewLine);source_sha256=$file.sha256;commit=$commit});$part++}}
}

$intelligenceFlows=[System.Collections.Generic.List[object]]::new()
foreach($flow in $catalog.flows){
    $triggerSpan=Get-SourceSpanForCatalogTrigger $flow.trigger $fileByPath $commit;$steps=[System.Collections.Generic.List[object]]::new()
    foreach($step in $flow.steps){$id="module:$step";$stepEvidence=@();if($entityById.ContainsKey($id)){$stepEvidence=@($entityById[$id].evidence)};$steps.Add([ordered]@{entity_id=$id;label=$step;evidence=$stepEvidence})}
    $intelligenceFlows.Add([ordered]@{id=$flow.id;label=$flow.label;primary=[bool]$flow.primary;trigger=[ordered]@{label=$flow.trigger.label;path=$flow.trigger.path;symbol=$flow.trigger.symbol;evidence=@($triggerSpan)};steps=@($steps);outcome=$flow.outcome;tests=@($flow.tests)})
}

$overviewPair=[ordered]@{};$overviewTypeMap=@{imports="imports";constructs="calls";calls="calls";reads="reads";writes="writes";publishes="publishes";subscribes="subscribes";tests="calls"}
foreach($relation in ($relations|Where-Object{$overviewTypeMap.ContainsKey($_.type) -and $_.status -eq "resolved"})){
    $fromEntity=$entityById[$relation.from];$toEntity=$entityById[$relation.to];if(-not $fromEntity -or -not $toEntity){continue};$from=$fromEntity.module_id;$to=$toEntity.module_id;if(-not $from -or -not $to -or $from -eq $to){continue}
    $fromOverview=$from.Substring("module:".Length);$toOverview=$to.Substring("module:".Length);$fromKnown=@($catalog.overview_nodes|Where-Object{$_.id -eq $fromOverview}).Count -gt 0;$toKnown=@($catalog.overview_nodes|Where-Object{$_.id -eq $toOverview}).Count -gt 0;if(-not $fromKnown -or -not $toKnown){continue}
    $type=$overviewTypeMap[$relation.type];$key="$fromOverview|$toOverview|$type";if(-not $overviewPair.Contains($key)){$overviewPair[$key]=[ordered]@{from=$fromOverview;to=$toOverview;type=$type;evidence=[System.Collections.Generic.List[object]]::new()}};if($overviewPair[$key].evidence.Count -lt 4){$overviewPair[$key].evidence.Add($relation.evidence[0])}
}
$overviewEdges=[System.Collections.Generic.List[object]]::new();foreach($pair in $overviewPair.Values|Sort-Object from,to,type){$overviewEdges.Add([ordered]@{from=$pair.from;to=$pair.to;type=$pair.type;evidence=@($pair.evidence|ForEach-Object{[ordered]@{path=$_.path;symbol=$_.symbol}})})}

$moduleTestMap=@{}
foreach($relation in $relations|Where-Object{$_.type -eq "tests" -and $_.status -eq "resolved"}){
    $testEntity=$entityById[$relation.from];$target=$entityById[$relation.to];if(-not $testEntity -or -not $target){continue};if(-not $moduleTestMap.ContainsKey($target.module_id)){$moduleTestMap[$target.module_id]=[System.Collections.Generic.List[string]]::new()};if($testEntity.path -and -not $moduleTestMap[$target.module_id].Contains($testEntity.path)){$moduleTestMap[$target.module_id].Add($testEntity.path)}
}
$overviewNodes=[System.Collections.Generic.List[object]]::new()
foreach($node in $catalog.overview_nodes){
    $moduleId="module:$($node.id)";$evidence=@();$symbols=@($entities|Where-Object{$_.module_id -eq $moduleId -and $_.kind -in @("class","function","signal","property","enum")}|Select-Object -First 6);foreach($symbol in $symbols){$evidence+=[ordered]@{path=$symbol.path;symbol=[string]$symbol.evidence[0].symbol}};if($evidence.Count -eq 0){$evidence=@([ordered]@{path="tools/source-intelligence/catalog.json";symbol=[string]$node.id})};$tests=@();if($moduleTestMap.ContainsKey($moduleId)){$tests=@($moduleTestMap[$moduleId])}
    $overviewNodes.Add([ordered]@{id=$node.id;path=$node.path;kind=$node.kind;boundary=$node.boundary;role=$node.role;entrypoints=@($node.entrypoints);tests=$tests;constraints=@($node.constraints);evidence=$evidence})
}
$overviewFlows=[System.Collections.Generic.List[object]]::new();foreach($flow in $catalog.flows){$overviewFlows.Add([ordered]@{id=$flow.id;label=$flow.label;trigger=[ordered]@{label=$flow.trigger.label;path=$flow.trigger.path;symbol=$flow.trigger.symbol};steps=@($flow.steps);outcome=$flow.outcome;primary=[bool]$flow.primary})}

foreach($relation in $relations){
    $evidenceKey=@($relation.evidence|ForEach-Object{"$($_.path):$($_.start_line):$($_.start_column):$($_.end_line):$($_.end_column):$($_.symbol)"}) -join ";"
    $relationKey="$($relation.from)|$($relation.to)|$($relation.type)|$($relation.status)|$($relation.resolver)|$evidenceKey"
    $relation.id="relation:"+(Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($relationKey))).Substring(0,24)
}

$moduleFingerprint=Get-ModuleFingerprints $inputPaths
$model=[ordered]@{schema_version=1;generator_version=$generatorVersion;repository=[ordered]@{name="Realmz Remake 2.0";commit=$commit;working_tree_dirty=$dirtyBefore;generated_at=$effectiveGeneratedAt};scope=$scopeRoots+$rootFiles;exclusions=$excludedDirectoryText+$generatedNames;files=@($fileRecords|Sort-Object path);entities=@($entities|Sort-Object id);relations=@($relations|Sort-Object from,type,to,id);flows=@($intelligenceFlows|Sort-Object id);diagnostics=@($diagnostics);search_documents=@($searchDocuments|Sort-Object id)}
Test-Model $model $fileByPath $commit

$overview=[ordered]@{generated_at=$effectiveGeneratedAt;generated_from_commit=$commit;scope=$scopeRoots+$rootFiles;nodes=@($overviewNodes);edges=@($overviewEdges);flows=@($overviewFlows)}
$chunkText=(@($chunks|Sort-Object id|ForEach-Object{Get-CanonicalJson $_}) -join [Environment]::NewLine)+[Environment]::NewLine
$intelligenceText=Get-CanonicalJson $model;$overviewText=Get-CanonicalJson $overview;$template=Get-Content -Raw $templatePath;$overviewHtmlText=$overviewText.Replace("</script","<\/script");$intelligenceHtmlText=$intelligenceText.Replace("</script","<\/script");$htmlText=$template.Replace("@@OVERVIEW_JSON@@",$overviewHtmlText).Replace("@@INTELLIGENCE_JSON@@",$intelligenceHtmlText)

$stage=Join-Path $outputRoot (".stage-" + [Guid]::NewGuid().ToString("N"));New-Item -ItemType Directory -Path $stage -Force|Out-Null
try{
    [IO.File]::WriteAllText((Join-Path $stage "codemap.json"),$overviewText,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage "intelligence.json"),$intelligenceText,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage "chunks.jsonl"),$chunkText,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage "codemap.html"),$htmlText,[Text.UTF8Encoding]::new($false))
    $outputHashes=[ordered]@{};foreach($name in @("codemap.html","codemap.json","intelligence.json","chunks.jsonl")){$outputHashes[$name]=Get-Sha256Bytes([IO.File]::ReadAllBytes((Join-Path $stage $name)))}
    $lock=[ordered]@{schema_version=1;generator_version=$generatorVersion;current_commit=$commit;working_tree_has_uncommitted_changes=$dirtyBefore;generated_at=$effectiveGeneratedAt;input_fingerprint=$inputFingerprint;scanned_scope=$scopeRoots+$rootFiles;excluded_directories=$excludedDirectoryText+$generatedNames;fingerprint_algorithm="sha256(UTF-8 path bytes, NUL, exact current file bytes, LF; lexical path order; module roots independently hashed)";module_fingerprints=$moduleFingerprint;output_hashes=$outputHashes;generated_files=$generatedNames}
    [IO.File]::WriteAllText((Join-Path $stage "codemap.lock"),(Get-CanonicalJson $lock),[Text.UTF8Encoding]::new($false))
    Test-WrittenArtifacts $stage
    foreach($name in $generatedNames){$source=Join-Path $stage $name;$destination=Join-Path $outputRoot $name;Move-Item -LiteralPath $source -Destination $destination -Force}
    Write-Host ("Source intelligence generated: {0} files, {1} entities, {2} relations, {3} flows, {4} chunks." -f $fileRecords.Count,$entities.Count,$relations.Count,$intelligenceFlows.Count,$chunks.Count)
}finally{if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}}
