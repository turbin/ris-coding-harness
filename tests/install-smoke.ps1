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

  # -Agent claude,opencode,codex installs the skill to .agents plus all three agent dirs.
  $Multi = Join-Path $Tmp "multi"
  New-Item -ItemType Directory -Force -Path $Multi | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Multi -Mode adopt -NoGit -Agent claude,opencode,codex | Out-Null
  Assert-True (Test-Path (Join-Path $Multi ".agents/skills/pm-workers-engineering/SKILL.md")) "multi .agents skill"
  Assert-True (Test-Path (Join-Path $Multi ".claude/skills/pm-workers-engineering/SKILL.md")) "multi .claude skill"
  Assert-True (Test-Path (Join-Path $Multi ".opencode/skills/pm-workers-engineering/SKILL.md")) "multi .opencode skill"
  Assert-True (Test-Path (Join-Path $Multi ".codex/skills/pm-workers-engineering/SKILL.md")) "multi .codex skill"

  # -Agent may be passed repeatedly.
  $Repeat = Join-Path $Tmp "repeat"
  New-Item -ItemType Directory -Force -Path $Repeat | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Repeat -Mode adopt -NoGit -Agent claude -Agent pi | Out-Null
  Assert-True (Test-Path (Join-Path $Repeat ".agents/skills/pm-workers-engineering/SKILL.md")) "repeat .agents skill"
  Assert-True (Test-Path (Join-Path $Repeat ".claude/skills/pm-workers-engineering/SKILL.md")) "repeat .claude skill"
  Assert-True (Test-Path (Join-Path $Repeat ".pi/skills/pm-workers-engineering/SKILL.md")) "repeat .pi skill"

  # Unknown agent must fail with exit code 2.
  $Bad = Join-Path $Tmp "bad"
  New-Item -ItemType Directory -Force -Path $Bad | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Bad -Mode adopt -NoGit -Agent foo | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "unknown agent must exit 2"
  Assert-True (-not (Test-Path (Join-Path $Bad "AGENTS.md"))) "unknown agent must abort before installing"

  Write-Host "install smoke test: PASS"
}
finally {
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
