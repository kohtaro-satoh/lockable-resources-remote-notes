<#
.SYNOPSIS
    Builds the Windows container image used to run the plugin unit tests, and cleans up
    the images that earlier builds left behind.

.DESCRIPTION
    See ../PLAN.md. The image carries JDK 21, Maven 3.9.9, MinGit, a real clone of the
    fork, and a local Maven repository warmed at the PR's merge base. Nothing is stored
    in a volume - a rebuild is the only way to refresh what the image holds.

    Build modes:
      (default)      incremental - reuses cached layers, so editing docker/run-test.ps1
                     rebuilds in seconds
      -CleanBuild    rebuilds every layer from scratch (docker build --no-cache).
                     ~10 minutes, almost all of it the Maven warm-up.

    Cleanup, in increasing order of what it takes away:
      -Cleanup       remove every dangling image (docker image prune -f). Those are the
                     leftovers of earlier builds; the current image's own layer chain is
                     referenced by its tag and survives, so incremental rebuilds stay fast.
      -PurgeImage    also remove the tagged image, so the next build is a full one. The
                     base images stay, so that rebuild needs no network fetch.
      -PurgeAll      also remove every unused image including the bases
                     (docker system prune -af). The next build re-pulls ~4 GB.
      -CleanupOnly   clean and exit without building. A purge switch on its own implies it.

    The cleanup is deliberately unscoped: this machine keeps no long-lived Windows
    containers, and everything here is reproducible from the repository, so the worst
    case of over-cleaning is a full rebuild plus a base image pull.

.EXAMPLE
    .\build-image.ps1                          # incremental
    .\build-image.ps1 -CleanBuild -Cleanup     # from scratch, then reclaim the old layers
    .\build-image.ps1 -CleanupOnly             # just reclaim disk
    .\build-image.ps1 -CleanupOnly -PurgeImage # drop the image too
    .\build-image.ps1 -CleanupOnly -PurgeAll   # wipe everything, bases included
    .\build-image.ps1 -PurgeAll                # wipe everything, then build from nothing
#>
[CmdletBinding()]
param(
    [string]$Tag = 'lrr-win-test:ltsc2022-jdk21',

    # Hyper-V isolated build containers default to 1 GB, which is not enough for the
    # Maven warm-up. This is the build-time counterpart of run-test.ps1's -Memory.
    [string]$Memory = '4g',

    [Alias('NoCache')]
    [switch]$CleanBuild,

    [switch]$Cleanup,

    [switch]$CleanupOnly,

    [switch]$PurgeImage,

    [switch]$PurgeAll
)

$ErrorActionPreference = 'Stop'

function Write-Disk([string]$label) {
    $row = @(docker system df --format '{{.Type}}: {{.TotalCount}} items, {{.Size}}, reclaimable {{.Reclaimable}}') |
        Where-Object { $_ -like 'Images*' }
    Write-Host "  disk [$label] $row" -ForegroundColor DarkGray
}

# $Level is passed explicitly rather than read from the switches, because the post-build
# call must stay at 'dangling' no matter what was asked for - a purge after the build
# would delete the image the build just produced.
function Invoke-Cleanup([ValidateSet('dangling', 'image', 'all')][string]$Level) {
    Write-Host ''
    Write-Host "=== Cleanup ($Level) ===" -ForegroundColor Cyan
    Write-Disk 'before'

    if ($Level -eq 'image' -or $Level -eq 'all') {
        $exists = @(docker images -q $Tag)
        if ($exists) {
            Write-Host "Removing tagged image $Tag (the next build will be a full one)" -ForegroundColor Yellow
            & docker rmi $Tag
        } else {
            Write-Host "No image tagged $Tag to remove"
        }
    }

    if ($Level -eq 'all') {
        # Everything unused, base images included. The next build re-pulls the ~4 GB
        # servercore/Temurin base over the network on top of the full rebuild.
        Write-Host 'docker system prune -af (unused images incl. base images)' -ForegroundColor Yellow
        & docker system prune -af
    } else {
        # Dangling = untagged AND unreferenced, i.e. the leftovers of superseded builds.
        # The layer chain behind the still-tagged image is referenced by its descendants
        # and survives, so an incremental rebuild stays fast.
        $dangling = @(docker images -f dangling=true --format '{{.ID}}  {{.Size}}  created {{.CreatedSince}}')
        if ($dangling.Count -eq 0) {
            Write-Host 'No dangling images to remove.'
        } else {
            Write-Host "Removing $($dangling.Count) dangling image(s):"
            $dangling | ForEach-Object { Write-Host "  $_" }
            # Their now-unreferenced ancestor layers are reclaimed by the same call.
            & docker image prune -f
        }
    }

    Write-Disk 'after'
}

$purging = $PurgeImage -or $PurgeAll
if ($PurgeAll) { $level = 'all' } elseif ($PurgeImage) { $level = 'image' } else { $level = 'dangling' }

if ($CleanupOnly -or ($purging -and -not $CleanBuild -and -not $Cleanup)) {
    Invoke-Cleanup $level
    exit 0
}

# ---------------------------------------------------------------- build

$contextDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'docker'
if (-not (Test-Path (Join-Path $contextDir 'Dockerfile'))) {
    throw "Dockerfile not found under $contextDir"
}

# A Linux-mode daemon would fail deep inside the build with a confusing error.
$osType = (docker info --format '{{.OSType}}') 2>$null
if ($osType -ne 'windows') {
    throw "Docker is in '$osType' container mode. Switch Docker Desktop to Windows containers first."
}

# A purge asked for alongside a build means "wipe first, then build from what is left".
if ($purging) { Invoke-Cleanup $level }

$dockerArgs = @(
    'build'
    '--isolation=hyperv'
    '-m', $Memory
    '-t', $Tag
)
if ($CleanBuild) { $dockerArgs += '--no-cache' }
$dockerArgs += $contextDir

Write-Host "docker $($dockerArgs -join ' ')" -ForegroundColor Cyan
if ($CleanBuild) {
    Write-Host 'Clean build: expect ~10 minutes (the Maven warm-up dominates).' -ForegroundColor Yellow
} else {
    Write-Host 'Incremental build: cached layers are reused where the Dockerfile is unchanged.' -ForegroundColor Yellow
}
Write-Disk 'before build'

$started = Get-Date
& docker @dockerArgs
$code = $LASTEXITCODE
$elapsed = (Get-Date) - $started

if ($code -ne 0) {
    Write-Host "Build FAILED after $([int]$elapsed.TotalMinutes)m (exit $code)" -ForegroundColor Red
    # Deliberately no cleanup on failure: the intermediate layers are what a retry
    # resumes from, and the failed step's container is worth inspecting.
    exit $code
}

Write-Host "Build OK in $([int]$elapsed.TotalMinutes)m$($elapsed.Seconds)s" -ForegroundColor Green
& docker images $Tag

# 'dangling' only: the image that was just built must survive its own cleanup.
if ($Cleanup) { Invoke-Cleanup 'dangling' }
