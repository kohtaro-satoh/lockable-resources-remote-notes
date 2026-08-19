# escape=`
#
# Windows container image for running the lockable-resources-plugin unit tests.
#
# See ../PLAN.md for why this image looks the way it does. The short version:
#   - Hyper-V isolation is the only option on this host (build 26200 has no matching
#     base image), so host bind mounts go over virtual SMB and are slow. Everything
#     the build touches therefore lives inside the container: C:\src\lrp, C:\m2, C:\t.
#   - .mvn/extensions.xml pulls in git-changelist-maven-extension, which reads .git.
#     The source has to be a real clone, not a file copy.
#   - The fork is public, so the clone is anonymous HTTPS. No credentials, no SSH key.
#   - The local repository is warmed at the PR's merge base and baked into a layer.
#     The branch does not touch pom.xml, so that cache covers the branch as well.
#
FROM eclipse-temurin:21-jdk-windowsservercore-ltsc2022

SHELL ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue';"]

# dlcdn.apache.org only carries the current release and 404s on 3.9.9; archive.apache.org
# keeps every version, which is what a reproducible image needs.
ARG MAVEN_VERSION=3.9.9
ARG MAVEN_URL=https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip
ARG MINGIT_URL=https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.4/MinGit-2.55.0.4-64-bit.zip
ARG PLUGIN_REPO_URL=https://github.com/kohtaro-satoh/lockable-resources-plugin.git
# The PR's merge base. Warming here keeps the cache valid for the branch too.
ARG WARM_REV=148d8eb

# Long paths, three ways. The Jenkins test harness digs deep temp directories and
# MAX_PATH is the classic way a Windows-only run dies with an unrelated error.
RUN Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Type DWord; `
    New-Item -ItemType Directory -Force -Path C:\t, C:\m2, C:\src, C:\tools, C:\out, C:\bin | Out-Null

RUN Invoke-WebRequest -Uri $env:MAVEN_URL -OutFile C:\maven.zip; `
    Expand-Archive -Path C:\maven.zip -DestinationPath C:\tools -Force; `
    Rename-Item -Path ('C:\tools\apache-maven-' + $env:MAVEN_VERSION) -NewName 'maven'; `
    Remove-Item C:\maven.zip

# MinGit rather than the full installer: it is a self-contained zip with the HTTPS
# backend and CA bundle, which is all the clone/checkout needs.
RUN Invoke-WebRequest -Uri $env:MINGIT_URL -OutFile C:\mingit.zip; `
    Expand-Archive -Path C:\mingit.zip -DestinationPath C:\tools\git -Force; `
    Remove-Item C:\mingit.zip

# NOT `ENV PATH=...`: this image carries no PATH in its config (only JAVA_VERSION), so
# `${PATH}` would expand to nothing and an ENV PATH would shadow the machine value that
# actually puts java, cmd and powershell on the path. Amend the machine variable instead,
# the way the Temurin image itself does. .NET rather than setx, which truncates at 1024.
RUN $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine'); `
    [Environment]::SetEnvironmentVariable('PATH', 'C:\tools\maven\bin;C:\tools\git\cmd;' + $machinePath, 'Machine')

ENV MAVEN_OPTS="-Xmx2g" `
    TEMP="C:\t" `
    TMP="C:\t"

RUN git config --system core.longpaths true; `
    git config --system core.autocrlf false; `
    git config --system safe.directory '*'

RUN git clone --no-single-branch $env:PLUGIN_REPO_URL C:\src\lrp; `
    if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE" }

WORKDIR C:\src\lrp

# The mvn arguments MUST stay single-quoted. PowerShell 5.1 splits an unquoted native
# argument that starts with '-' at its first '.', so `-Dmaven.repo.local=C:\m2` reaches
# Maven as `-Dmaven` plus a bogus goal `.repo.local=C:\m2`. Verified on this host:
#   unquoted        -> [-B -ntp -Dstyle .color=never -Dmaven .repo.local=C:\m2 test-compile]
#   single-quoted   -> [-B -ntp -Dstyle.color=never -Dmaven.repo.local=C:\m2 test-compile]
# Arguments without a leading '-' (git's `core.longpaths`) are unaffected.
#
# Every native command needs its own $LASTEXITCODE check. PowerShell's ';' does not stop
# on a non-zero exit from a native command, not even under $ErrorActionPreference='Stop',
# so an unchecked `git checkout` that failed would silently warm the wrong revision and
# still produce a green layer.
RUN git fetch --all --tags --prune; `
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed with exit code $LASTEXITCODE" }; `
    git checkout --detach $env:WARM_REV; `
    if ($LASTEXITCODE -ne 0) { throw "git checkout $env:WARM_REV failed with exit code $LASTEXITCODE" }; `
    mvn '-B' '-ntp' '-Dstyle.color=never' '-Dmaven.repo.local=C:\m2' 'test-compile'; `
    if ($LASTEXITCODE -ne 0) { throw "warm-up build failed with exit code $LASTEXITCODE" }; `
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue C:\src\lrp\target

# Last layer on purpose: iterating on the runner rebuilds seconds, not the warm cache.
COPY run-test.ps1 C:/bin/run-test.ps1

ENTRYPOINT ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\bin\\run-test.ps1"]
