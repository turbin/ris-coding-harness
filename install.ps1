#!/usr/bin/env pwsh
#requires -Version 5.1
<#
.SYNOPSIS
  Project engineering bootstrap installer (Windows / PowerShell port of install.sh).

.PARAMETER Target
  Target project directory (default: .)

.PARAMETER Mode
  auto | init | adopt (default: auto)
  auto   Use init for an empty/near-empty directory, otherwise adopt
  init   Create the canonical engineering directory skeleton
  adopt  Add agent routing/rules/skill without restructuring source layout

.PARAMETER Force
  Overwrite managed files created by this installer.

.PARAMETER NoGit
  Do not initialize a Git repository.

.PARAMETER NoSkill
  Do not install the PM-Workers skill.

.PARAMETER Agent
  Additionally install the skill to agent-specific directories.
  Values: claude, pi, kimi, kimi-code, opencode, codex, agents, all.
  Accepts comma-separated names and/or repeated parameters.

.PARAMETER Scope
  project | user (default: project) — resolve agent skill directories
  under the target project or under the user home.

.EXAMPLE
  .\install.ps1 -Target .\my-project -Mode init

.EXAMPLE
  .\install.ps1 -Target .\my-project -Agent claude,opencode -Scope project

.EXAMPLE
  irm https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.ps1 | iex
  # or download first, then: powershell -ExecutionPolicy Bypass -File install.ps1 -Target .
#>
[CmdletBinding()]
param(
  [string]$Target = ".",
  [ValidateSet("auto", "init", "adopt")]
  [string]$Mode = "auto",
  [switch]$Force,
  [switch]$NoGit,
  [switch]$NoSkill,
  [string[]]$Agent = @(),
  [ValidateSet("project", "user")]
  [string]$Scope = "project",
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo = if ($env:PROJECT_INIT_REPO) { $env:PROJECT_INIT_REPO } else { "turbin/ris-coding-harness" }
$Ref  = if ($env:PROJECT_INIT_REF)  { $env:PROJECT_INIT_REF }  else { "main" }

function Show-Usage {
  @'
Project engineering bootstrap installer (PowerShell)

Usage:
  install.ps1 [options]

Options:
  -Target PATH           Target project directory (default: .)
  -Mode auto|init|adopt  Initialization mode (default: auto)
  -Force                 Overwrite managed files created by this installer
  -NoGit                 Do not initialize a Git repository
  -NoSkill               Do not install the PM-Workers skill
  -Agent NAMES           Also install the skill to agent-specific directories.
                         Values: claude, pi, kimi, kimi-code, opencode, codex,
                         agents, all. Comma-separated and/or repeated.
  -Scope project|user    Resolve agent directories under the target project
                         or the user home (default: project)
  -Help                  Show this help

Modes:
  auto   Use init for an empty/near-empty directory, otherwise adopt
  init   Create the canonical engineering directory skeleton
  adopt  Add agent routing/rules/skill without restructuring source layout

Examples:
  .\install.ps1 -Target my-project -Mode init
  .\install.ps1 -Target existing-project -Mode adopt
  .\install.ps1 -Target my-project -Agent claude,opencode
  .\install.ps1 -Target my-project -Agent pi -Scope user
'@ | Write-Host
}

if ($Help) { Show-Usage; exit 0 }

# --- Resolve target -----------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Target | Out-Null
$TargetRoot = (Resolve-Path $Target).Path

function Get-RelPath([string]$Path) {
  if ($Path.StartsWith($TargetRoot)) {
    return $Path.Substring($TargetRoot.Length).TrimStart('\', '/')
  }
  return $Path
}

# --- Agent skill destinations ---------------------------------------------------
$AgentMap = @{
  "claude"    = @{ project = ".claude/skills";   user = ".claude/skills" }
  "pi"        = @{ project = ".pi/skills";       user = ".pi/agent/skills" }
  "kimi"      = @{ project = ".kimi/skills";     user = ".kimi/skills" }
  "kimi-code" = @{ project = ".kimi/skills";     user = ".kimi/skills" }
  "opencode"  = @{ project = ".opencode/skills"; user = ".config/opencode/skills" }
  "codex"     = @{ project = ".codex/skills";    user = ".codex/skills" }
  "agents"    = @{ project = ".agents/skills";   user = ".agents/skills" }
}

function Get-SkillDest([string]$Name) {
  $rel = $AgentMap[$Name][$Scope]
  $prefix = if ($Scope -eq "user") { $HOME } else { $TargetRoot }
  return Join-Path $prefix $rel
}

$RequestedAgents = @()
foreach ($item in $Agent) {
  foreach ($name in ($item -split ',')) {
    $n = $name.Trim().ToLowerInvariant()
    if ([string]::IsNullOrEmpty($n)) { continue }
    if ($n -eq "all") {
      foreach ($k in $AgentMap.Keys) {
        if ($RequestedAgents -notcontains $k) { $RequestedAgents += $k }
      }
      continue
    }
    if (-not $AgentMap.ContainsKey($n)) {
      [Console]::Error.WriteLine("Unknown agent: $n")
      [Console]::Error.WriteLine("Supported agents: $(($AgentMap.Keys | Sort-Object) -join ', '), all")
      exit 2
    }
    if ($RequestedAgents -notcontains $n) { $RequestedAgents += $n }
  }
}

# .agents/skills is always installed; agent destinations are deduplicated on top.
$SkillDests = @((Join-Path $TargetRoot ".agents/skills"))
foreach ($a in $RequestedAgents) {
  $d = Get-SkillDest $a
  if ($SkillDests -notcontains $d) { $SkillDests += $d }
}

# --- Resolve source root (local checkout or remote download) ------------------
$TmpRoot = $null
try {
  $SourceRoot = $null
  if ($PSScriptRoot -and
      (Test-Path (Join-Path $PSScriptRoot "templates/project/AGENTS.md")) -and
      (Test-Path (Join-Path $PSScriptRoot "skills/pm-workers-engineering/SKILL.md"))) {
    $SourceRoot = $PSScriptRoot
  }
  else {
    $TmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ris-bootstrap-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null
    $Archive = Join-Path $TmpRoot "source.zip"
    Write-Host "Downloading $Repo@$Ref ..."
    Invoke-WebRequest -Uri "https://github.com/$Repo/archive/$Ref.zip" -OutFile $Archive -UseBasicParsing
    Expand-Archive -Path $Archive -DestinationPath $TmpRoot -Force
    $SourceRoot = Get-ChildItem -Path $TmpRoot -Directory |
      Where-Object { $_.Name -ne "source" } |
      Select-Object -First 1 -ExpandProperty FullName
    if (-not $SourceRoot -or -not (Test-Path (Join-Path $SourceRoot "templates/project/AGENTS.md"))) {
      Write-Error "Installer templates not found in $Repo@$Ref"
    }
  }

  # --- Helpers (mirror install.sh semantics) ------------------------------------
  function Managed-Copy([string]$Src, [string]$Dst) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
    if ((Test-Path $Dst) -and -not $Force) {
      Write-Host ("keep   {0}" -f (Get-RelPath $Dst))
      return
    }
    Copy-Item $Src $Dst -Force
    Write-Host ("write  {0}" -f (Get-RelPath $Dst))
  }

  function Write-If-Missing([string]$Dst, [string]$Content) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
    if ((Test-Path $Dst) -and -not $Force) {
      Write-Host ("keep   {0}" -f (Get-RelPath $Dst))
      return
    }
    [System.IO.File]::WriteAllText($Dst, ($Content -replace "`r?`n", [System.Environment]::NewLine) + [System.Environment]::NewLine)
    Write-Host ("write  {0}" -f (Get-RelPath $Dst))
  }

  function Install-SkillTo([string]$Dest, [string]$SkillSrcPath) {
    $SkillName = Split-Path -Leaf $SkillSrcPath
    Get-ChildItem $SkillSrcPath -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($SkillSrcPath.Length).TrimStart('\', '/')
      Managed-Copy $_.FullName (Join-Path $Dest ($SkillName + "/" + $rel))
    }
  }

  function Test-NearEmpty {
    $count = (Get-ChildItem -Force $TargetRoot |
      Where-Object { $_.Name -ne ".git" -and $_.Name -ne ".DS_Store" } |
      Measure-Object).Count
    return ($count -eq 0)
  }

  if ($Mode -eq "auto") {
    if (Test-NearEmpty) { $Mode = "init" } else { $Mode = "adopt" }
  }

  Write-Host "Project bootstrap: mode=$Mode target=$TargetRoot"

  # --- Core files ---------------------------------------------------------------
  Managed-Copy (Join-Path $SourceRoot "templates/project/AGENTS.md") (Join-Path $TargetRoot "AGENTS.md")
  Get-ChildItem (Join-Path $SourceRoot "templates/project/docs/engineering") -Filter *.md | ForEach-Object {
    Managed-Copy $_.FullName (Join-Path $TargetRoot ("docs/engineering/" + $_.Name))
  }

  if (-not $NoSkill) {
    $SkillsRoot = Join-Path $SourceRoot "skills"
    foreach ($skillDir in (Get-ChildItem $SkillsRoot -Directory)) {
      foreach ($dest in $SkillDests) {
        Install-SkillTo $dest $skillDir.FullName
      }
    }
  }

  $RsiSrc = Join-Path $SourceRoot "templates/project/.rsi"
  if (Test-Path $RsiSrc) {
    Get-ChildItem $RsiSrc -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($RsiSrc.Length).TrimStart('\', '/')
      Managed-Copy $_.FullName (Join-Path $TargetRoot (".rsi/" + $rel))
    }
  }

  $IndexBody = @'
# Index

Use this file as a lightweight navigation surface. Keep entries concise and point to the detailed artifact instead of duplicating it.

| Time | File | Summary |
|---|---|---|
'@

  if ($Mode -eq "init") {
    foreach ($d in @("src", "tests", "docs", "decisions", "issues", "conversations", "output", "progress", "scripts", "tmp")) {
      New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot $d) | Out-Null
      if ($d -ne "docs" -or -not (Test-Path (Join-Path $TargetRoot "$d/index.md"))) {
        Write-If-Missing (Join-Path $TargetRoot "$d/index.md") $IndexBody
      }
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot "evals/results") | Out-Null
    Write-If-Missing (Join-Path $TargetRoot "evals/index.md") $IndexBody
  }

  # Always provide routing indexes for project-management records when the directory exists.
  foreach ($d in @("decisions", "issues", "progress")) {
    if (Test-Path (Join-Path $TargetRoot $d)) {
      Write-If-Missing (Join-Path $TargetRoot "$d/index.md") $IndexBody
    }
  }

  if (-not (Test-Path (Join-Path $TargetRoot ".gitignore"))) {
    $Gitignore = @'
# Dependencies / virtual environments
node_modules/
.venv/
venv/

# Build outputs
build/
dist/

# Caches
__pycache__/
*.py[cod]
.cache/

# Environment / secrets
.env
.env.*
!.env.example

# Temporary project artifacts
tmp/*
!tmp/index.md

# OS / editor noise
.DS_Store
Thumbs.db
.idea/
.vscode/
'@
    [System.IO.File]::WriteAllText((Join-Path $TargetRoot ".gitignore"), $Gitignore + [System.Environment]::NewLine)
    Write-Host "write  .gitignore"
  }
  else {
    Write-Host "keep   .gitignore"
  }

  if (-not $NoGit) {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
      if (-not (Test-Path (Join-Path $TargetRoot ".git"))) {
        git -C $TargetRoot init -b main 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { git -C $TargetRoot init | Out-Null }
        Write-Host "init   .git"
      }
      else {
        Write-Host "keep   .git"
      }
    }
    else {
      Write-Warning "git not found; repository not initialized"
    }
  }

  Write-Host ""
  Write-Host "Bootstrap complete."
  Write-Host "Next: fill docs/engineering/index.md and only the rule files relevant to this project."
  Write-Host "Agent entry: AGENTS.md"
  if (-not $NoSkill) {
    foreach ($d in $SkillDests) {
      Write-Host ("Skills: " + (Get-RelPath (Join-Path $d "{pm-workers-engineering,rsi-loop}/SKILL.md")))
    }
  }
}
finally {
  if ($TmpRoot -and (Test-Path $TmpRoot)) {
    Remove-Item -Recurse -Force $TmpRoot -ErrorAction SilentlyContinue
  }
}
