#!/usr/bin/env pwsh
#requires -Version 5.1
# Smoke test for install.ps1 — Windows counterpart of tests/install-smoke.sh.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ris-smoke-" + [System.Guid]::NewGuid().ToString("N"))

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

try {
  $New = Join-Path $Tmp "new"
  $Existing = Join-Path $Tmp "existing"
  New-Item -ItemType Directory -Force -Path $New, $Existing | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Existing "package.json"), '{"name":"existing-demo"}')

  & (Join-Path $Root "install.ps1") -Target $New -Mode auto -NoGit | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode auto -NoGit | Out-Null

  # Empty project should receive canonical init layout.
  Assert-True (Test-Path (Join-Path $New "AGENTS.md")) "new/AGENTS.md"
  Assert-True (Test-Path (Join-Path $New "src/index.md")) "new/src/index.md"
  Assert-True (Test-Path (Join-Path $New "tests/index.md")) "new/tests/index.md"
  Assert-True (Test-Path (Join-Path $New "docs/engineering/index.md")) "new/docs/engineering/index.md"
  Assert-True (Test-Path (Join-Path $New ".agents/skills/pm-workers-engineering/SKILL.md")) "new skill"
  Assert-True (Test-Path (Join-Path $New ".rsi/policy.yaml")) "new .rsi/policy.yaml"
  Assert-True (Test-Path (Join-Path $New "evals/results")) "new evals/results"

  # Existing project should be adopted without canonical source/test directories.
  Assert-True (Test-Path (Join-Path $Existing "AGENTS.md")) "existing/AGENTS.md"
  Assert-True (Test-Path (Join-Path $Existing "docs/engineering/index.md")) "existing rules index"
  Assert-True (Test-Path (Join-Path $Existing ".agents/skills/pm-workers-engineering/SKILL.md")) "existing skill"
  Assert-True (-not (Test-Path (Join-Path $Existing "src"))) "existing must not get src/"
  Assert-True (-not (Test-Path (Join-Path $Existing "tests"))) "existing must not get tests/"
  Assert-True (Test-Path (Join-Path $Existing "package.json")) "package.json preserved"

  # Re-running must be non-destructive without -Force.
  [System.IO.File]::WriteAllText((Join-Path $Existing "docs/engineering/coding.md"), "# local customization`n")
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode adopt -NoGit | Out-Null
  $coding = Get-Content (Join-Path $Existing "docs/engineering/coding.md") -Raw
  Assert-True ($coding -match "^# local customization") "local customization preserved"

  Write-Host "install smoke test: PASS"
}
finally {
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
