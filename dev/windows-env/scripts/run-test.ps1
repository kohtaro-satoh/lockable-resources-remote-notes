<#
.SYNOPSIS
    Runs the plugin unit tests in the Windows container and writes a report under
    dev/reports/.

.DESCRIPTION
    See ../PLAN.md. The container does the work (docker/run-test.ps1, the image's
    ENTRYPOINT); this script starts it, copies C:\out back with `docker cp`, and turns
    the surefire XML into a Markdown summary.

    There is no volume and no bind mount, so `docker cp` from the stopped container is
    the only way results come back - which is why --rm is not used.

    Run the control revision before the branch:
        .\run-test.ps1 -Rev 148d8eb          # the PR's merge base
        .\run-test.ps1 -Rev bdca858          # the branch
    A failure that only appears on the second is the one worth reading.

.EXAMPLE
    .\run-test.ps1 -Rev 148d8eb -Test LockableResourceTest      # smoke
    .\run-test.ps1 -Rev bdca858                                 # the real thing
    .\run-test.ps1 -Rev bdca858 -Repeat 5                       # flaky or not?
    .\run-test.ps1 -Rev bdca858 -ExtraMvnArgs '-DforkCount=1C'  # match CI more closely
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Rev,

    [string]$Test = 'LockStepWithRestartTest',

    [int]$Repeat = 1,

    [string]$ExtraMvnArgs = '',

    # Hyper-V isolated containers default to 1 GB. The restart tests will not survive
    # that, and the resulting OOM looks nothing like the failure we are chasing.
    [string]$Memory = '8g',

    [int]$Cpus = 6,

    [string]$Tag = 'lrr-win-test:ltsc2022-jdk21',

    # Leave the container in place for `docker exec` / `docker logs` poking.
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1's Out-File -Encoding utf8 emits a BOM, which shows up as a stray glyph
# at the top of the committed Markdown. These files are repository content, so write them
# the way the rest of the repo is written.
function Write-Utf8([string[]]$lines, [string]$path) {
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"),
        (New-Object System.Text.UTF8Encoding $false))
}

$notesRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)   # .../dev
$reportsDir = Join-Path $notesRepo 'reports'
$repoRoot = Split-Path -Parent $notesRepo

# ---------------------------------------------------------------- preflight

$osType = (docker info --format '{{.OSType}}') 2>$null
if ($osType -ne 'windows') {
    throw "Docker is in '$osType' container mode. Switch Docker Desktop to Windows containers first."
}
if (-not @(docker images -q $Tag)) {
    throw "Image $Tag not found. Build it first: .\build-image.ps1"
}
$imageId = (docker images -q $Tag)

New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null

$ts = Get-Date -Format 'yyyyMMddHHmmss'
$slug = "$ts-windows-unittest"
$outDir = Join-Path $reportsDir $slug
$reportMd = Join-Path $reportsDir "$slug.md"
$container = "lrr-win-test-$ts"

# Provenance. Unlike run-mvn-verify.sh this does not refuse a dirty tree: the plugin
# source is cloned inside the container, so the host's working trees have no bearing on
# what gets tested. The harness SHA is recorded so the report still says what produced it.
$harnessSha = (git -C $repoRoot rev-parse --short HEAD 2>$null)
if (-not $harnessSha) { $harnessSha = 'unknown' }
if (@(git -C $repoRoot status --porcelain 2>$null).Count -gt 0) {
    $harnessSha = "$harnessSha + local changes"
}

# ---------------------------------------------------------------- run

$dockerArgs = @(
    'run'
    '--isolation=hyperv'
    '--memory', $Memory
    '--cpus', "$Cpus"
    '--name', $container
    $Tag
    '-Rev', $Rev
    '-TestPattern', $Test
    '-Repeat', "$Repeat"
)
if ($ExtraMvnArgs.Trim()) { $dockerArgs += @('-ExtraMvnArgs', $ExtraMvnArgs) }

Write-Host "docker $($dockerArgs -join ' ')" -ForegroundColor Cyan
Write-Host "Report will be written to $reportMd" -ForegroundColor DarkGray

$started = Get-Date
$ErrorActionPreference = 'Continue'
# ForEach-Object { "$_" } flattens the ErrorRecords that 2>&1 makes out of the container's
# stderr back into plain lines. Without it every stderr line arrives wrapped in
# "docker.exe : ... + CategoryInfo ... NativeCommandError" noise, in the console and in
# the captured log alike.
& docker @dockerArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable runOut | Write-Host
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$elapsed = (Get-Date) - $started

# ---------------------------------------------------------------- collect

if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
$staged = Join-Path $reportsDir 'out'
if (Test-Path $staged) { Remove-Item -Recurse -Force $staged }

& docker cp "${container}:C:\out" $reportsDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: docker cp failed; the container produced no C:\out" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
} else {
    Rename-Item -Path $staged -NewName $slug
}

Write-Utf8 $runOut (Join-Path $outDir 'docker-run.log')

if ($Keep) {
    Write-Host "-Keep: container '$container' left running/stopped for inspection" -ForegroundColor Yellow
} else {
    & docker rm $container | Out-Null
}

# ---------------------------------------------------------------- report

function Get-FailedCases($dir) {
    $cases = @()
    Get-ChildItem -Path $dir -Recurse -Filter 'TEST-*.xml' -ErrorAction SilentlyContinue | ForEach-Object {
        $file = $_
        try { [xml]$xml = Get-Content -Raw -LiteralPath $file.FullName } catch { return }
        foreach ($tc in @($xml.testsuite.testcase | Where-Object { $_ })) {
            foreach ($kind in @('failure', 'error')) {
                $node = $tc.$kind
                if (-not $node) { continue }
                $cases += [pscustomobject]@{
                    Run     = Split-Path (Split-Path $file.FullName -Parent) -Leaf
                    Case    = "$($tc.classname)#$($tc.name)"
                    Kind    = $kind
                    Type    = $node.type
                    Message = $node.message
                    Detail  = $node.'#text'
                }
            }
        }
    }
    return $cases
}

function Get-RunTotals($dir) {
    $totals = @()
    Get-ChildItem -Path $dir -Directory -Filter 'run-*' -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object {
            $runDir = $_
            $tests = 0; $fail = 0; $err = 0; $skip = 0; $found = $false
            Get-ChildItem -Path $runDir.FullName -Recurse -Filter 'TEST-*.xml' -ErrorAction SilentlyContinue | ForEach-Object {
                try { [xml]$xml = Get-Content -Raw -LiteralPath $_.FullName } catch { return }
                $found = $true
                $tests += [int]$xml.testsuite.tests
                $fail += [int]$xml.testsuite.failures
                $err += [int]$xml.testsuite.errors
                $skip += [int]$xml.testsuite.skipped
            }
            if ($found) { $verdict = $(if ($fail + $err -eq 0) { 'PASS' } else { 'FAIL' }) } else { $verdict = 'NO REPORTS' }
            $totals += [pscustomobject]@{
                Run = $runDir.Name; Verdict = $verdict
                Tests = $tests; Failures = $fail; Errors = $err; Skipped = $skip
            }
        }
    return $totals
}

function Add-Log($sb, $title, $path) {
    if (-not (Test-Path $path)) { return }
    $lines = @(Get-Content -LiteralPath $path)
    $note = ''
    if ($lines.Count -gt 2000) {
        $note = "`n> Truncated to the last 2000 of $($lines.Count) lines. The full file is in ``$slug/``.`n"
        $lines = $lines[-2000..-1]
    }
    [void]$sb.AppendLine("<details><summary>$title</summary>")
    [void]$sb.AppendLine($note)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine(($lines -join "`n"))
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine('</details>')
    [void]$sb.AppendLine('')
}

$totals = Get-RunTotals $outDir
$failed = Get-FailedCases $outDir
if ($code -eq 0) { $result = 'PASS' } else { $result = 'FAIL' }

# The container resolves the requested rev to a SHA and records it; that resolved value
# is what the report cites, so a stale ref cannot pass itself off as the requested one.
$envTxt = Join-Path $outDir 'env.txt'
$revHead = 'n/a'
if (Test-Path $envTxt) {
    $line = @(Get-Content -LiteralPath $envTxt) | Where-Object { $_ -like 'rev.head*' } | Select-Object -First 1
    if ($line) { $revHead = ($line -split ':', 2)[1].Trim() }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# Windows container unit test report ($ts)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine("- Result: **$result** (exit $code)")
[void]$sb.AppendLine("- Duration: $([int]$elapsed.TotalMinutes)m$($elapsed.Seconds)s")
[void]$sb.AppendLine("- Revision requested: ``$Rev``")
[void]$sb.AppendLine("- Revision tested: ``$revHead``")
[void]$sb.AppendLine("- Test pattern: ``$Test``  (repeat $Repeat)")
if ($ExtraMvnArgs.Trim()) { [void]$sb.AppendLine("- Extra mvn args: ``$ExtraMvnArgs``") }
[void]$sb.AppendLine("- Image: ``$Tag`` (``$imageId``), hyperv isolation, memory $Memory, cpus $Cpus")
[void]$sb.AppendLine("- Harness (notes): ``$harnessSha``")
[void]$sb.AppendLine("- Raw artifacts: ``$slug/``")
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Runs')
[void]$sb.AppendLine('')
if ($totals.Count -eq 0) {
    [void]$sb.AppendLine('No surefire reports were produced. The build failed before the tests ran - see the log below.')
} else {
    [void]$sb.AppendLine('| Run | Verdict | Tests | Failures | Errors | Skipped |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|')
    foreach ($t in $totals) {
        [void]$sb.AppendLine("| $($t.Run) | $($t.Verdict) | $($t.Tests) | $($t.Failures) | $($t.Errors) | $($t.Skipped) |")
    }
}
[void]$sb.AppendLine('')

if ($failed.Count -gt 0) {
    [void]$sb.AppendLine('## Failures')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> Which of the two sessions did this happen in? `sessions.then(...)` block 1 sets up')
    [void]$sb.AppendLine('> the reservation and restarts; block 2 unreserves and waits for the lock. The frames')
    [void]$sb.AppendLine('> below `JenkinsSessionExtension` tell them apart.')
    [void]$sb.AppendLine('')
    foreach ($f in $failed) {
        [void]$sb.AppendLine("### $($f.Case) ($($f.Run), $($f.Kind))")
        [void]$sb.AppendLine('')
        if ($f.Type) { [void]$sb.AppendLine("- Type: ``$($f.Type)``") }
        if ($f.Message) { [void]$sb.AppendLine("- Message: $($f.Message)") }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine($f.Detail)
        [void]$sb.AppendLine('```')
        [void]$sb.AppendLine('')
    }
}

[void]$sb.AppendLine('## Logs')
[void]$sb.AppendLine('')
foreach ($t in $totals) {
    Add-Log $sb "mvn log ($($t.Run))" (Join-Path (Join-Path $outDir $t.Run) 'mvn.log')
}
Add-Log $sb 'docker run console output' (Join-Path $outDir 'docker-run.log')

Write-Utf8 ($sb.ToString() -split "`r?`n") $reportMd

Write-Host ''
if ($result -eq 'PASS') {
    Write-Host "Result: PASS  ($([int]$elapsed.TotalMinutes)m$($elapsed.Seconds)s)" -ForegroundColor Green
} else {
    Write-Host "Result: FAIL (exit $code)  ($([int]$elapsed.TotalMinutes)m$($elapsed.Seconds)s)" -ForegroundColor Red
    foreach ($f in $failed) { Write-Host "  $($f.Run): $($f.Case) [$($f.Kind)] $($f.Message)" -ForegroundColor Red }
}
Write-Host "Report:  $reportMd"
Write-Host "Raw:     $outDir"

exit $code
