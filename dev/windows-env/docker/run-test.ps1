<#
.SYNOPSIS
    Runs the plugin unit tests inside the Windows container. Baked into the image
    as C:\bin\run-test.ps1 and used as the ENTRYPOINT.

.DESCRIPTION
    Checks out a revision, runs `mvn test` for a test pattern, and leaves everything
    a post-mortem needs under C:\out. The host copies that directory out with
    `docker cp` after the container stops - there is no volume and no bind mount,
    so C:\out is the only channel back.

    Exits non-zero if any repetition failed. That is the signal the host reads.
#>
[CmdletBinding()]
param(
    # Revision to test. The whole point of this harness is running the same test at
    # two of them: 148d8eb (the PR's merge base, the control) and bdca858 (the branch).
    [Parameter(Mandatory = $true)][string]$Rev,

    [string]$TestPattern = 'LockStepWithRestartTest',

    # >1 to tell a genuine failure apart from a flaky one.
    [int]$Repeat = 1,

    # Extra -D flags, space separated. e.g. '-DforkCount=1C'
    [string]$ExtraMvnArgs = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepoDir = 'C:\src\lrp'
$OutDir = 'C:\out'
$M2Dir = 'C:\m2'

function Write-Section($text) {
    Write-Host ''
    Write-Host "=== $text ===" -ForegroundColor Cyan
}

# `java -version` and `mvn -v` write to stderr. Under $ErrorActionPreference='Stop',
# PowerShell 5.1 turns a native command's stderr into ErrorRecords as soon as it is
# merged with 2>&1, so `(& java -version 2>&1)` throws on a perfectly healthy JDK.
# Collect tool versions through here instead of redirecting inline.
# These files are copied out and committed, and PowerShell 5.1's `Out-File -Encoding utf8`
# writes a BOM. Match the rest of the repository instead.
function Write-Utf8([string[]]$lines, [string]$path) {
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"),
        (New-Object System.Text.UTF8Encoding $false))
}

function Get-ToolVersion([string]$exe, [string[]]$argv) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $exe @argv 2>&1 | ForEach-Object { "$_" }
        return (($out | Where-Object { $_.Trim() }) -join ' | ')
    } catch {
        return "<unavailable: $($_.Exception.Message)>"
    } finally {
        $ErrorActionPreference = $prev
    }
}

if (Test-Path $OutDir) { Remove-Item -Recurse -Force "$OutDir\*" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---------------------------------------------------------------- checkout

Write-Section "Checking out $Rev"
Set-Location $RepoDir
git fetch --all --tags --prune
if ($LASTEXITCODE -ne 0) {
    # Not fatal: the image already carries both revisions, so an offline run is still
    # valid. The resolved SHA below is what the report cites, so a stale ref cannot pass
    # itself off as the requested one.
    Write-Host "WARNING: git fetch failed (exit $LASTEXITCODE); continuing with what the image holds"
}
git checkout --detach $Rev
if ($LASTEXITCODE -ne 0) { throw "git checkout $Rev failed" }
# Belt and braces: the image ships no target/, but a stale one would silently mix
# classes from the control revision into the branch run.
git clean -xdff | Out-Null

$headLine = (git log -1 --format='%H %ci %s')
Write-Host $headLine

# ---------------------------------------------------------------- provenance

Write-Section 'Environment'
$envLines = @(
    "rev.requested   : $Rev"
    "rev.head        : $headLine"
    "test.pattern    : $TestPattern"
    "repeat          : $Repeat"
    "extra.mvn.args  : $ExtraMvnArgs"
    ''
    "os              : $((Get-CimInstance Win32_OperatingSystem).Caption) build $([Environment]::OSVersion.Version)"
    "cpu.count       : $env:NUMBER_OF_PROCESSORS"
    "memory.total.mb : $([int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB))"
    "temp            : $env:TEMP"
    ''
    "java            : $(Get-ToolVersion 'java' @('-version'))"
    "maven           : $(Get-ToolVersion 'mvn' @('-v'))"
    "git             : $(Get-ToolVersion 'git' @('--version'))"
)
$envLines | Tee-Object -Variable envOut | Write-Host
Write-Utf8 $envOut (Join-Path $OutDir 'env.txt')

# ---------------------------------------------------------------- run

$mvnArgs = @(
    '-B'
    '-ntp'
    '-Dstyle.color=never'
    "-Dmaven.repo.local=$M2Dir"
    "-Dtest=$TestPattern"
)
if ($ExtraMvnArgs.Trim()) {
    $mvnArgs += @($ExtraMvnArgs.Split(' ') | Where-Object { $_ })
}
$mvnArgs += 'test'

$results = @()
for ($i = 1; $i -le $Repeat; $i++) {
    Write-Section "Run $i/$Repeat : mvn $($mvnArgs -join ' ')"
    $runDir = Join-Path $OutDir "run-$i"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null

    # A previous repetition's reports must not be mistaken for this one's.
    $reports = Join-Path $RepoDir 'target\surefire-reports'
    if (Test-Path $reports) { Remove-Item -Recurse -Force $reports }

    # PowerShell 5.1 turns native stderr into ErrorRecords under 'Stop', which would
    # abort the script on Maven's first warning. Maven's exit code is the verdict here.
    $ErrorActionPreference = 'Continue'
    # ForEach-Object { "$_" } flattens the ErrorRecords 2>&1 makes of Maven's stderr back
    # into plain lines; without it every warning arrives wrapped in NativeCommandError noise.
    & mvn @mvnArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable mvnOut | Write-Host
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'

    Write-Utf8 $mvnOut (Join-Path $runDir 'mvn.log')
    if (Test-Path $reports) {
        Copy-Item -Recurse -Force $reports (Join-Path $runDir 'surefire-reports')
    } else {
        Write-Host "WARNING: no surefire-reports produced (the build failed before the tests?)"
    }

    $results += [pscustomobject]@{ Run = $i; ExitCode = $code }
    Write-Host "Run $i/$Repeat exit code: $code"
}

# ---------------------------------------------------------------- summary

Write-Section 'Summary'
$summary = @("rev      : $headLine", "pattern  : $TestPattern", '')
foreach ($r in $results) {
    if ($r.ExitCode -eq 0) { $verdict = 'PASS' } else { $verdict = 'FAIL' }
    $summary += "run $($r.Run): $verdict (exit $($r.ExitCode))"
}

# The surefire XML carries the full stack trace even when the console output is
# truncated, so name the failing cases here to point the reader at the right file.
$failedCases = @()
Get-ChildItem -Path $OutDir -Recurse -Filter '*.xml' -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        [xml]$xml = Get-Content -Raw -LiteralPath $_.FullName
        foreach ($tc in $xml.testsuite.testcase) {
            if ($tc.failure -or $tc.error) {
                $failedCases += "$($tc.classname)#$($tc.name)  ->  $($_.FullName)"
            }
        }
    } catch { }
}
if ($failedCases.Count -gt 0) {
    $summary += ''
    $summary += 'failed cases:'
    $summary += ($failedCases | Sort-Object -Unique | ForEach-Object { "  $_" })
}

$summary | Write-Host
Write-Utf8 $summary (Join-Path $OutDir 'summary.txt')

$failedRuns = @($results | Where-Object { $_.ExitCode -ne 0 })
if ($failedRuns.Count -gt 0) { exit 1 }
exit 0
