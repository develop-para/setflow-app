<#
.SYNOPSIS
    Builds a signed release APK and uploads it to Firebase App Distribution.

.DESCRIPTION
    Setflow's backend is Supabase, so the app itself carries no Firebase SDK.
    Firebase is used purely as a tester-distribution channel: the CLI uploads
    the APK, Firebase emails the testers, and the app binary stays untouched.

    Versioning matches .github/workflows/android-distribute.yml exactly, so a
    build made here and a build made by CI can never collide:

      versionName  = the x.y.z in pubspec.yaml (bump by hand for real releases)
      versionCode  = git rev-list --count HEAD (commit count on the branch)

    Every distributed build is tagged dist/<versionCode>, which is also where
    the next run's release notes start from.

    Prerequisites (one time) are in docs/android-distribution.md.

.EXAMPLE
    pwsh tool/distribute-android.ps1

.EXAMPLE
    pwsh tool/distribute-android.ps1 -Notes "Rest timer widget fixes" -Arm64Only
#>
[CmdletBinding()]
param(
    # Firebase Android App ID. Falls back to tool/firebase-distribution.json,
    # then to the FIREBASE_ANDROID_APP_ID environment variable.
    [string]$AppId,

    # Comma-separated Firebase App Distribution tester groups.
    [string]$Groups,

    # Comma-separated tester emails (in addition to the groups).
    [string]$Testers,

    # Google account the Firebase CLI should act as. The CLI keeps one global
    # default account per machine, which may belong to an unrelated project, so
    # naming the account here keeps this repo independent of that default and
    # portable to other machines. Run `firebase login:add <email>` once first.
    [string]$Account,

    # Release notes shown to testers. Generated from the commits since the last
    # dist/* tag when omitted.
    [string]$Notes,

    # Build for arm64 only. The universal APK carries three ABIs (~70 MB);
    # arm64-v8a alone covers essentially every test device made since 2017 and
    # roughly halves the download. Use the universal build if any tester is on
    # an x86 emulator or a pre-2017 device.
    [switch]$Arm64Only,

    # Distribute a build number that was already distributed. Android refuses
    # to install it over the existing one, so this is only for re-uploading a
    # broken artifact.
    [switch]$Force,

    # Skip creating and pushing the dist/<versionCode> tag.
    [switch]$NoTag,

    # Build the APK but skip the upload - useful for a local smoke test.
    [switch]$NoUpload
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$configPath = Join-Path $PSScriptRoot 'firebase-distribution.json'

function Write-Step($message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Invoke-Git {
    param([string[]]$Arguments)
    $output = & git -C $repoRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $output"
    }
    return $output
}

# --- Resolve configuration -------------------------------------------------

$config = $null
if (Test-Path $configPath) {
    # -Encoding UTF8 is not optional: the tester group alias is Korean, and
    # Windows PowerShell 5.1 reads a BOM-less file as the ANSI codepage. On a
    # Korean install that turns the alias into mojibake, and Firebase answers a
    # bare 404 for a group nobody can see is wrong.
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-Setting($explicit, $configKey, $envName, $fallback) {
    if (-not [string]::IsNullOrWhiteSpace($explicit)) { return $explicit }
    if ($null -ne $config -and $config.PSObject.Properties.Name -contains $configKey) {
        $value = $config.$configKey
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    if (-not [string]::IsNullOrWhiteSpace($envName)) {
        $envValue = [Environment]::GetEnvironmentVariable($envName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) { return $envValue }
    }
    return $fallback
}

$AppId = Resolve-Setting $AppId 'appId' 'FIREBASE_ANDROID_APP_ID' ''
$Groups = Resolve-Setting $Groups 'groups' '' ''
$Testers = Resolve-Setting $Testers 'testers' '' ''
$Account = Resolve-Setting $Account 'account' 'FIREBASE_ACCOUNT' ''

if (-not $NoUpload -and [string]::IsNullOrWhiteSpace($AppId)) {
    throw "Firebase App ID is not set. Add `"appId`" to tool/firebase-distribution.json, set FIREBASE_ANDROID_APP_ID, or pass -AppId."
}
if (-not $NoUpload -and [string]::IsNullOrWhiteSpace($Groups) -and [string]::IsNullOrWhiteSpace($Testers)) {
    throw "No recipients. Set `"groups`" or `"testers`" in tool/firebase-distribution.json, or pass -Groups / -Testers."
}

# --- Preflight: signing key ------------------------------------------------

$keyProperties = Join-Path $repoRoot 'android/key.properties'
if (-not (Test-Path $keyProperties)) {
    throw "android/key.properties is missing, so the release APK would be signed with the debug key. Testers could not install updates over it. Restore the keystore before distributing."
}

# --- Resolve version -------------------------------------------------------

$pubspec = Get-Content $pubspecPath -Raw
# Match trailing blanks with [ \t]* rather than \s* - in multiline mode a greedy
# \s* runs past the line ending and swallows the blank line that follows.
if ($pubspec -notmatch '(?m)^version:[ \t]*([0-9]+\.[0-9]+\.[0-9]+)') {
    throw "Could not parse `"version: x.y.z`" from pubspec.yaml."
}
$versionName = $Matches[1]
$buildNumber = [int](Invoke-Git @('rev-list', '--count', 'HEAD'))

$lastTag = ''
$tags = & git -C $repoRoot tag -l 'dist/*' --sort=-version:refname
if ($LASTEXITCODE -eq 0 -and $tags) {
    $lastTag = @($tags)[0]
}

if (-not $Force -and -not [string]::IsNullOrWhiteSpace($lastTag)) {
    $lastNumber = [int]($lastTag -replace '^dist/', '')
    if ($buildNumber -le $lastNumber) {
        throw "Build $buildNumber was already distributed as $lastTag. Android refuses to install a build whose versionCode is not higher, so testers would never receive this one. Commit your work first (the build number is the commit count), or pass -Force to re-upload anyway."
    }

    # versionName rule (docs/versioning.md): every distribution bumps x.y.z —
    # feat in the batch means MINOR+, otherwise PATCH. Without this gate the
    # name sat at 1.0.0 for a hundred builds and meant nothing to testers.
    $lastPubspec = & git -C $repoRoot show "${lastTag}:pubspec.yaml" 2>$null
    if ($LASTEXITCODE -eq 0 -and $lastPubspec) {
        $lastVersionLine = @($lastPubspec) | Where-Object { $_ -match '^version:' } | Select-Object -First 1
        if ($lastVersionLine -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
            $lastVersionName = $Matches[1]
            if ($lastVersionName -eq $versionName) {
                throw "versionName $versionName is unchanged since $lastTag. Rule: every distribution bumps pubspec's x.y.z - MINOR for feature batches, PATCH for fix-only ones (docs/versioning.md). Bump it, commit, and rerun; or pass -Force if you really mean to reship the same name."
            }
        }
    }
}

Write-Host "Distributing Setflow $versionName+$buildNumber (previous: $(if ($lastTag) { $lastTag } else { 'none' }))" -ForegroundColor Green

# --- Release notes ---------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($Notes)) {
    $range = if ($lastTag) { "$lastTag..HEAD" } else { 'HEAD~20..HEAD' }
    $log = & git -C $repoRoot log --no-merges --pretty=format:'- %s' $range
    if ($LASTEXITCODE -ne 0 -or -not $log) {
        $log = & git -C $repoRoot log --no-merges --pretty=format:'- %s' -n 20
    }
    $Notes = (@($log) -join "`n").Trim()
}
if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "Setflow $versionName ($buildNumber)"
}
if ($Notes.Length -gt 3000) {
    $Notes = $Notes.Substring(0, 3000)
}

Write-Step "Release notes"
Write-Host $Notes

# --- Build -----------------------------------------------------------------

Push-Location $repoRoot
try {
    $buildArgs = @(
        'build', 'apk', '--release',
        "--build-name=$versionName",
        "--build-number=$buildNumber"
    )

    if ($Arm64Only) {
        $buildArgs += @('--target-platform', 'android-arm64')
    }

    # Optional build-time configuration (Supabase overrides, OAuth toggles).
    # See tool/dart-defines.example.json.
    $dartDefines = Join-Path $repoRoot 'dart-defines.json'
    if (Test-Path $dartDefines) {
        Write-Host "Using dart-defines.json for build-time configuration."
        $buildArgs += "--dart-define-from-file=dart-defines.json"
    }

    Write-Step "flutter $($buildArgs -join ' ')"
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE." }
}
finally {
    Pop-Location
}

$apkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path $apkPath)) {
    throw "Build reported success but $apkPath does not exist."
}
$apkSizeMb = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
Write-Host "APK ready: $apkPath ($apkSizeMb MB)"

if ($NoUpload) {
    Write-Step "-NoUpload set - skipping Firebase App Distribution."
    return
}

# --- Upload ----------------------------------------------------------------

$distributeArgs = @(
    'appdistribution:distribute', $apkPath,
    '--app', $AppId,
    '--release-notes', $Notes
)
if (-not [string]::IsNullOrWhiteSpace($Groups)) {
    $distributeArgs += @('--groups', $Groups)
}
if (-not [string]::IsNullOrWhiteSpace($Testers)) {
    $distributeArgs += @('--testers', $Testers)
}
if (-not [string]::IsNullOrWhiteSpace($Account)) {
    $distributeArgs += @('--account', $Account)
}

Write-Step "firebase appdistribution:distribute"
& firebase @distributeArgs
if ($LASTEXITCODE -ne 0) { throw "firebase appdistribution:distribute failed with exit code $LASTEXITCODE." }

# --- Record the build ------------------------------------------------------

if (-not $NoTag) {
    $tag = "dist/$buildNumber"
    $existing = & git -C $repoRoot tag -l $tag
    if ($existing) {
        Write-Host "Tag $tag already exists - leaving it alone." -ForegroundColor Yellow
    }
    else {
        Invoke-Git @('tag', '-a', $tag, '-m', "Setflow $versionName+$buildNumber distributed to testers") | Out-Null
        Write-Host "Tagged $tag"
        # PS 5.1에서 네이티브 명령에 2>&1을 걸면 git이 stderr로 쓰는 성공
        # 메시지("To https://...")까지 ErrorRecord로 감싸 스크립트가 exit 1로
        # 끝난다 — 배포가 다 되고도 실패로 보고된 원인. stderr는 건드리지
        # 않고 $LASTEXITCODE만 본다.
        & git -C $repoRoot push origin $tag | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Could not push $tag to origin. Push it manually so the next build's notes start from here: git push origin $tag" -ForegroundColor Yellow
        }
        else {
            Write-Host "Pushed $tag to origin"
        }
    }
}

# 노션 배포 기록 — CI와 같은 스크립트, 같은 DB. 실패해도 배포는 이미 끝났으니 경고만.
if (-not $NoTag) {
    Write-Step "notion release record"
    & dart tool/notion_release_note.dart --build $buildNumber --version $versionName --by 자동
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Could not record the build in Notion. Run later: dart tool/notion_release_note.dart --build $buildNumber" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Distributed Setflow $versionName+$buildNumber to Firebase App Distribution." -ForegroundColor Green
