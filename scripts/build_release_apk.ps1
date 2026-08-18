[CmdletBinding()]
param(
    [string]$NasDirectory = $env:SETFLOW_NAS_APK_DIR,
    [switch]$RequireNas
)

$ErrorActionPreference = 'Stop'
$defaultNasDirectory = '\\192.168.123.101\Bef_UserPhoto\teampara'
if ([string]::IsNullOrWhiteSpace($NasDirectory)) {
    $NasDirectory = $defaultNasDirectory
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
$outputDirectory = Join-Path $projectRoot 'artifacts\apk'
$nasIsRequired = $RequireNas -or $env:SETFLOW_NAS_REQUIRED -eq '1'

Push-Location $projectRoot
try {
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter release APK build failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
        throw "Release APK was not created at $sourceApk."
    }

    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMddHH'
    $destinationApk = Join-Path $outputDirectory "${timestamp}_setflow.apk"
    Copy-Item -LiteralPath $sourceApk -Destination $destinationApk -Force

    $resolvedApk = (Resolve-Path -LiteralPath $destinationApk).Path
    Write-Output "APK saved: $resolvedApk"

    if ([string]::IsNullOrWhiteSpace($NasDirectory)) {
        if ($nasIsRequired) {
            throw 'SETFLOW_NAS_APK_DIR is required but is not configured.'
        }
        Write-Warning 'NAS upload skipped: SETFLOW_NAS_APK_DIR is not configured.'
        return
    }

    if (-not [IO.Path]::IsPathRooted($NasDirectory)) {
        throw 'SETFLOW_NAS_APK_DIR must be an absolute local, mapped-drive, or UNC path.'
    }

    $nasDestinationApk = Join-Path $NasDirectory "${timestamp}_setflow.apk"
    $nasTemporaryApk = "$nasDestinationApk.uploading"
    try {
        New-Item -ItemType Directory -Force -Path $NasDirectory | Out-Null
        Copy-Item -LiteralPath $resolvedApk -Destination $nasTemporaryApk -Force
        Move-Item -LiteralPath $nasTemporaryApk -Destination $nasDestinationApk -Force
        $resolvedNasApk = (Resolve-Path -LiteralPath $nasDestinationApk).Path
        Write-Output "NAS APK saved: $resolvedNasApk"
    }
    catch {
        if (Test-Path -LiteralPath $nasTemporaryApk -PathType Leaf) {
            Remove-Item -LiteralPath $nasTemporaryApk -Force
        }
        if ($nasIsRequired) {
            throw
        }
        Write-Warning "NAS upload failed; the local APK is preserved. $($_.Exception.Message)"
    }
}
finally {
    Pop-Location
}
