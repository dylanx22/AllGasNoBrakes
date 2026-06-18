<#
.SYNOPSIS
  Build the CurseForge upload zip for All Gas No Brakes.

.DESCRIPTION
  CurseForge builds require a .zip whose top-level entry is the addon folder
  (AllGasNoBrakes/) containing the .toc and .lua files -- nothing else (no tests,
  docs, git, or tooling). This script copies only the shippable addon folder into
  dist/ and zips it as AllGasNoBrakes-v<version>.zip, reading the version from the
  .toc so the filename always matches what the client reports.

.EXAMPLE
  pwsh tools/package.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = "dist"
)

$ErrorActionPreference = "Stop"
$repo    = Split-Path -Parent $PSScriptRoot
$addon   = Join-Path $repo "AllGasNoBrakes"
$tocPath = Join-Path $addon "AllGasNoBrakes.toc"

if (-not (Test-Path $tocPath)) { throw "TOC not found at $tocPath" }

$version = (Select-String -Path $tocPath -Pattern '^##\s*Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
if (-not $version) { throw "Could not read ## Version from the .toc" }

$dist = Join-Path $repo $OutDir
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$zip = Join-Path $dist "AllGasNoBrakes-v$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

# Staging copy so the archive root is exactly "AllGasNoBrakes/<files>".
$stage = Join-Path $dist "_stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage "AllGasNoBrakes") | Out-Null
Copy-Item -Path (Join-Path $addon "*") -Destination (Join-Path $stage "AllGasNoBrakes") -Recurse

Compress-Archive -Path (Join-Path $stage "AllGasNoBrakes") -DestinationPath $zip
Remove-Item $stage -Recurse -Force

Write-Host "Packaged v$version -> $zip"
