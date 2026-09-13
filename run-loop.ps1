#!/usr/bin/env pwsh
#requires -Version 5.1
<#
.SYNOPSIS
  rsi-loop thin shell (PowerShell port of run-loop.sh). Builds the invocation
  prompt and hands it to an agent CLI. For interactive use, talk to your agent
  directly — this script exists for cron/CI (unattended) scenarios.

  The agent CLI is taken from:
    1. -AgentCmd
    2. RSI_AGENT_CMD environment variable
    3. RSI_AGENT_CANDIDATES (env var, or progress/loop/agent.env) — first match
    4. builtin default list: pi, opencode, claude, codex, kimi
#>
[CmdletBinding()]
param(
  [ValidateSet("observe-only", "l1-auto", "all-manual")]
  [string]$Gate = "observe-only",
  [int]$Rounds = 5,
  [string]$Queue = "",
  [switch]$Resume,
  [string]$AgentCmd = "",
  [string]$Candidates = "",
  [switch]$Headless,
  [switch]$DryRun,
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Help) {
  @'
rsi-loop thin shell (PowerShell)

Usage:
  run-loop.ps1 [-Gate LEVEL] [-Rounds N] [-Queue FILE] [-Resume]
               [-AgentCmd CMD] [-Headless] [-DryRun]

  -Gate LEVEL    observe-only | l1-auto | all-manual (default: observe-only)
  -Rounds N      rounds to run (default: 5)
  -Queue FILE    task queue (default: progress/loop/tasks.yaml)
  -Resume        resume from progress/loop/state.yaml
  -AgentCmd CMD  agent CLI command (default: $env:RSI_AGENT_CMD or first available)
  -Headless      non-interactive print mode (pi -p / kimi -p / claude -p /
                 codex exec / opencode run)
  -DryRun        print the invocation prompt without running
'@ | Write-Host
  exit 0
}

$ScriptDir = $PSScriptRoot
$AgentEnv = Join-Path $ScriptDir "progress/loop/agent.env"
if (Test-Path -LiteralPath $AgentEnv) {
  Get-Content -LiteralPath $AgentEnv | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      $name = $Matches[1]; $val = $Matches[2].Trim().Trim('"').Trim("'")
      if (-not (Test-Path "env:$name")) { Set-Item "env:$name" $val }
    }
  }
}

if (-not $AgentCmd -and $env:RSI_AGENT_CMD) { $AgentCmd = $env:RSI_AGENT_CMD }
if (-not $Candidates) {
  if ($env:RSI_AGENT_CANDIDATES) { $Candidates = $env:RSI_AGENT_CANDIDATES }
  else { $Candidates = "pi opencode claude codex kimi" }
}
if ($env:RSI_HEADLESS -eq "1") { $Headless = $true }

if (-not $AgentCmd) {
  foreach ($c in ($Candidates -split '[,\s]+' | Where-Object { $_ })) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $AgentCmd = $c; break }
  }
}
if (-not $AgentCmd) {
  [Console]::Error.WriteLine("No agent CLI found. Set RSI_AGENT_CMD (e.g. `$env:RSI_AGENT_CMD='pi' run-loop.ps1) or RSI_AGENT_CANDIDATES.")
  exit 2
}

$ResumeFlag = ""
if ($Resume) { $ResumeFlag = "--resume" }
$QueueFlag = ""
if ($Queue) { $QueueFlag = "--queue $Queue" }
$Prompt = "Invoke the rsi-loop skill (.harness/skills/rsi-loop/SKILL.md, or skills/rsi-loop/ in the harness repository) with: --gate $Gate --rounds $Rounds $QueueFlag $ResumeFlag. Read the skill and follow its procedure."

Write-Host ("gate: {0}   rounds: {1}   agent: {2}   headless: {3}   resume: {4}" -f $Gate, $Rounds, $AgentCmd, $(if ($Headless) { "yes" } else { "no" }), $(if ($Resume) { "yes" } else { "no" }))
if ($DryRun) {
  Write-Host "prompt: $Prompt"
  exit 0
}

function Invoke-Agent([string]$Cmd, [string]$PromptText) {
  $parts = $Cmd -split '\s+'
  $exe = $parts[0]
  $extraArgs = @()
  if ($parts.Count -gt 1) { $extraArgs = $parts[1..($parts.Count - 1)] }
  if ($Headless) {
    switch ($exe) {
      "pi"       { & pi -p $PromptText; return }
      "kimi"     { & kimi -p $PromptText; return }
      "claude"   { & claude -p $PromptText; return }
      "codex"    { & codex exec $PromptText; return }
      "opencode" { & opencode run $PromptText; return }
      default {
        Write-Warning "no headless mapping for '$exe'; passing prompt as a single argument"
      }
    }
  }
  & $exe @extraArgs $PromptText
}

Invoke-Agent $AgentCmd $Prompt
exit $LASTEXITCODE
