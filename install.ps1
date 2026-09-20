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

.PARAMETER Check
  Only verify that the required skills are present; write nothing.
  Exit 0 when all present, 1 when missing/incomplete, 2 on usage errors.

.PARAMETER Agent
  Additionally install the skill to agent-specific directories.
  Values: claude, pi, kimi, kimi-code, opencode, codex, agents, all.
  Accepts comma-separated names or an array of names; repeated -Agent
  parameters are not supported by PowerShell parameter binding.

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
  [string]$Mode = "auto",
  [switch]$Force,
  [switch]$NoGit,
  [switch]$NoSkill,
  [switch]$Check,
  [switch]$SkipEnv,
  [switch]$DryRunEnv,
  [switch]$StrictEnv,
  [string[]]$Agent = @(),
  [string]$Scope = "project",
  [string]$Search = "zvec",
  [switch]$Help,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RemainingArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:InstalledFiles = @()

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
  -Check                 Only verify required skills are present; write nothing.
                         Exit 0 when all present, 1 when missing/incomplete,
                         2 on usage errors
  -SkipEnv               Skip the environment bootstrap stage entirely
  -DryRunEnv             Print the env bootstrap commands without executing them
  -StrictEnv             Exit with code 3 when the env bootstrap stage fails
  -Agent NAMES           Also install the skill to agent-specific directories.
                         Values: claude, pi, kimi, kimi-code, opencode, codex,
                         agents, all. Comma-separated or an array; repeated
                         -Agent parameters cannot bind in PowerShell.
  -Scope project|user    Resolve agent directories under the target project
                         or the user home (default: project)
  -Search zvec|off       Workspace search routing (default: zvec). zvec injects
                         the search-routing section into AGENTS.md and
                         provisions the zg CLI (npm -g @zvec/zvec-grep) when
                         missing; off skips both
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

# Usage errors exit 2 (see README "Exit code contract"). Mode/Scope are
# validated manually instead of via ValidateSet so the exit code matches bash.
if (@("auto", "init", "adopt") -notcontains $Mode) {
  [Console]::Error.WriteLine("Invalid mode: $Mode")
  exit 2
}
if (@("project", "user") -notcontains $Scope) {
  [Console]::Error.WriteLine("Invalid scope: $Scope")
  exit 2
}
if (@("zvec", "off") -notcontains $Search) {
  [Console]::Error.WriteLine("Invalid search: $Search (want zvec|off)")
  exit 2
}
if ($RemainingArgs.Count -gt 0) {
  [Console]::Error.WriteLine("Unknown option: $($RemainingArgs[0])")
  exit 2
}

if ($Check -and $NoSkill) {
  [Console]::Error.WriteLine("-Check and -NoSkill are mutually exclusive")
  exit 2
}

# --- Resolve target -----------------------------------------------------------
if (Test-Path -LiteralPath $Target) {
  $TargetRoot = (Resolve-Path $Target).Path
}
elseif ($Check) {
  # Never create the target in check mode; an absent target simply means
  # every project-scoped destination is missing.
  $TargetRoot = $Target
}
else {
  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  $TargetRoot = (Resolve-Path $Target).Path
}

function Get-RelPath([string]$Path) {
  $sep = [System.IO.Path]::DirectorySeparatorChar
  if ($TargetRoot -eq ".") {
    # Check mode with a relative target that does not exist yet.
    if ($Path.StartsWith(".$sep")) { return $Path.Substring(2) }
    return $Path
  }
  # Require the separator after the prefix so a sibling directory
  # (target=C:\x, path=C:\xy\...) is not truncated.
  if ($Path.StartsWith($TargetRoot + $sep)) {
    return $Path.Substring($TargetRoot.Length + 1)
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
$SkillDests = @((Join-Path $TargetRoot ".harness/skills"))
foreach ($a in $RequestedAgents) {
  $d = Get-SkillDest $a
  if ($SkillDests -notcontains $d) { $SkillDests += $d }
}

# --- Resolve source root (local checkout or remote download) ------------------
$TmpRoot = $null
try {
  $SourceRoot = $null
  if ($PSScriptRoot -and
      (Test-Path (Join-Path $PSScriptRoot ".harness/templates/project/docs/engineering/index.md")) -and
      (Test-Path (Join-Path $PSScriptRoot ".harness/skills"))) {
    # Repo self-hosts its mechanism layer under .harness/ (G1).
    $SourceRoot = Join-Path $PSScriptRoot ".harness"
  }
  elseif ($PSScriptRoot -and
      (Test-Path (Join-Path $PSScriptRoot "templates/project/docs/engineering/index.md")) -and
      (Test-Path (Join-Path $PSScriptRoot "skills"))) {
    # Legacy repo layout (mechanism layer at repo root).
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
    if (Test-Path (Join-Path $SourceRoot ".harness/templates/project/docs/engineering/index.md")) {
      $SourceRoot = Join-Path $SourceRoot ".harness"
    }
    if (-not $SourceRoot -or -not (Test-Path (Join-Path $SourceRoot "templates/project/docs/engineering/index.md"))) {
      Write-Error "Installer templates not found in $Repo@$Ref"
    }
  }

  # --- Managed-section entry files (AGENTS.md / CLAUDE.md, G1) -------------------
  $script:BeginMark = "<!-- ris-coding-harness:begin -->"
  $script:EndMark = "<!-- ris-coding-harness:end -->"

  $AgentsSkel = @"
# Project Agent Entry

This file routes agents working in this repository. The marked section below
is generated and refreshed by the ris-coding-harness installer on every run;
content outside the markers is project-owned and is never modified by the
installer.
"@

  $ClaudeSkel = @"
# Claude Code notes

Only the harness-managed pointer below is required; add your own notes
outside the markers.
"@

  function Build-AgentsSection {
    $repair = ((Show-RepairHint | Out-String).Trim()) -replace "^Repair: ", ""
    $searchSection = ""
    if ($Search -eq "zvec") {
      $searchSection = @'
**Search routing (zvec is the default fuzzy-search layer)**

- Fuzzy/semantic lookups for code or evidence: `zg query --human "<question>"`.
  On first use run `zg status`, then `zg index` if missing (storage lives in
  `.zvec-grep/`, git-ignored); refresh with `zg index` after large changes.
- Exact string/symbol lookups: native Grep/Glob (or `zg query --rg`).
- Structure, relationships, architecture: `graphify` when `graphify-out/`
  exists; call graphs and blast radius: CodeGraph (`.codegraph/`).
- Verify retrieved evidence with native tools before editing.
'@
    }
    @"
$($script:BeginMark)
## Harness routing (managed by ris-coding-harness - do not edit between the markers)

**Skills (mechanism layer, inside `.harness/`)**

- `.harness/skills/pm-workers-engineering/SKILL.md` - PM-Workers protocol: PM decomposes, Coder TDD, Reviewer adversarial gate. Load role references only when the role is active.
- `.harness/skills/rsi-loop/SKILL.md` - RSI self-improvement loop. In this project it runs in observe-only self-check mode; the full loop runs only in the harness self-hosted repository.

**Engineering rules (decision layer, outside `.harness/`)**

- Start with `docs/engineering/index.md`; load only task-relevant rule files.
- `decisions/`, `issues/`, `progress/` hold project records - use each `index.md` before reading many child files.
- `evals/results/` receives structured reviewer verdicts.

$searchSection
**Harness mechanism boundary**

- `.harness/` holds everything the installer manages: skills, gate policy, manifest, reports. Do not hand-edit; re-run the installer to repair.
- The installer never restructures project source and never overwrites project files outside the managed section of this file.

**Self-check / self-heal**

If a required `SKILL.md` is missing or incomplete, re-run the installer - it only fills what is missing and refreshes this managed section:

$repair
$($script:EndMark)
"@
  }

  function Build-ClaudeSection {
    @"
$($script:BeginMark)
## Harness pointer (managed by ris-coding-harness - do not edit between the markers)

This project is managed by ris-coding-harness. The repository-root `AGENTS.md` is the single routing entry (skills, engineering rules, conventions) - read it instead of duplicating rules here. Required skills live under `.harness/skills/`; gate policy under `.harness/.rsi/policy.yaml`; the managed file list is `.harness/manifest.json`.
$($script:EndMark)
"@
  }

  function Merge-Managed([string]$File, [string]$Section, [string]$Skeleton) {
    if (-not (Test-Path -LiteralPath $File)) {
      [System.IO.File]::WriteAllText($File, $Skeleton + "`n`n" + $Section + "`n")
      Write-Host ("write  {0}" -f (Get-RelPath $File))
      $script:InstalledFiles += $File
      return
    }
    $existing = Get-Content -LiteralPath $File -Raw
    if ($existing.Contains($script:BeginMark)) {
      $pattern = "(?s)" + [regex]::Escape($script:BeginMark) + ".*?" + [regex]::Escape($script:EndMark)
      $updated = [regex]::Replace($existing, $pattern, { param($m) $Section })
      if (-not $updated.EndsWith("`n")) { $updated += "`n" }
      [System.IO.File]::WriteAllText($File, $updated)
      Write-Host ("merge  {0}" -f (Get-RelPath $File))
    }
    else {
      $sep = "`n"
      if ($existing.EndsWith("`n")) { $sep = "" }
      [System.IO.File]::WriteAllText($File, $existing + $sep + $Section + "`n")
      Write-Host ("merge  {0}" -f (Get-RelPath $File))
    }
    $script:InstalledFiles += $File
  }


  function Migrate-One([string]$File, [string]$LegacyRoot, [string]$SourceRoot, [string]$NewRoot) {
    $rel = $File.Substring($LegacyRoot.Length).TrimStart('\', '/')
    $src = Join-Path $SourceRoot $rel
    $dst = Join-Path $NewRoot $rel
    if (-not (Test-Path -LiteralPath $src)) {
      Write-Host ("legacy   {0} (no managed counterpart; left in place)" -f (Get-RelPath $File))
      return
    }
    # Only a legacy file byte-identical to the managed source may be moved or
    # deduplicated; anything else is user content and stays untouched.
    if ((Get-FileHash -LiteralPath $src).Hash -ne (Get-FileHash -LiteralPath $File).Hash) {
      if (Test-Path -LiteralPath $dst) {
        Write-Host ("legacy   {0} (differs from managed copy; left in place)" -f (Get-RelPath $File))
      } else {
        Write-Host ("legacy   {0} (customized; left in place)" -f (Get-RelPath $File))
      }
      return
    }
    if (Test-Path -LiteralPath $dst) {
      Remove-Item -LiteralPath $File -Force
    } else {
      New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
      Move-Item -LiteralPath $File -Destination $dst -Force
      $script:InstalledFiles += $dst
    }
  }

  function Migrate-Legacy {
    $ran = $false
    $legacySkills = Join-Path $TargetRoot ".agents/skills"
    if ((-not $NoSkill) -and (Test-Path -LiteralPath $legacySkills)) {
      Get-ChildItem -LiteralPath $legacySkills -Recurse -File | ForEach-Object {
        Migrate-One $_.FullName $legacySkills (Join-Path $SourceRoot "skills") (Join-Path $TargetRoot ".harness/skills")
      }
      Get-ChildItem -LiteralPath $legacySkills -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not ($_.GetFiles() -or $_.GetDirectories()) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
      $ran = $true
    }
    $legacyRsi = Join-Path $TargetRoot ".rsi"
    if (Test-Path -LiteralPath $legacyRsi) {
      Get-ChildItem -LiteralPath $legacyRsi -Recurse -File | ForEach-Object {
        Migrate-One $_.FullName $legacyRsi (Join-Path $SourceRoot "templates/project/.rsi") (Join-Path $TargetRoot ".harness/.rsi")
      }
      Get-ChildItem -LiteralPath $legacyRsi -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not ($_.GetFiles() -or $_.GetDirectories()) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
      $ran = $true
    }
    if ($ran) { Write-Host "migrate  legacy layout: identical files moved into .harness/; customized files left in place (see legacy lines above)" }
  }

  function Write-Manifest {
    $manDir = Join-Path $TargetRoot ".harness"
    New-Item -ItemType Directory -Force -Path $manDir | Out-Null
    $man = Join-Path $manDir "manifest.json"
    $skills = @()
    Get-ChildItem (Join-Path $SourceRoot "skills") -Directory | ForEach-Object { $skills += $_.Name }
    $dests = @()
    foreach ($d in $SkillDests) { $dests += (Get-RelPath $d) }
    $files = @()
    foreach ($f in $script:InstalledFiles) {
      if (-not (Test-Path -LiteralPath $f)) { continue }
      $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower()
      $files += [pscustomobject]@{ path = (Get-RelPath $f); sha256 = $h }
    }
    $obj = [pscustomobject]@{
      schema_version = 1
      generated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
      harness_repo = $Repo
      harness_ref = $Ref
      skills = $skills
      agent_destinations = $dests
      files = $files
    }
    $json = $obj | ConvertTo-Json -Depth 5
    # No BOM: manifest.json is machine-read by bash/python toolchains.
    [System.IO.File]::WriteAllText($man, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("write  {0}" -f (Get-RelPath $man))
  }

  # --- Helpers (mirror install.sh semantics) ------------------------------------
  function Managed-Copy([string]$Src, [string]$Dst) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
    if ((Test-Path $Dst) -and -not $Force) {
      Write-Host ("keep   {0}" -f (Get-RelPath $Dst))
      $script:InstalledFiles += $Dst
      return
    }
    Copy-Item $Src $Dst -Force
    $script:InstalledFiles += $Dst
    Write-Host ("write  {0}" -f (Get-RelPath $Dst))
  }

  function Write-If-Missing([string]$Dst, [string]$Content) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Dst -Parent) | Out-Null
    if ((Test-Path $Dst) -and -not $Force) {
      Write-Host ("keep   {0}" -f (Get-RelPath $Dst))
      $script:InstalledFiles += $Dst
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

  # Print one status line per required skill x destination and return $true
  # only when every required skill has its SKILL.md in every destination.
  function Test-RequiredSkills {
    $SkillsRoot = Join-Path $SourceRoot "skills"
    $failed = $false
    foreach ($skillDir in (Get-ChildItem $SkillsRoot -Directory)) {
      foreach ($dest in $SkillDests) {
        $skillPath = Join-Path $dest $skillDir.Name
        $rel = Get-RelPath $skillPath
        if (Test-Path (Join-Path $skillPath "SKILL.md")) {
          Write-Host ("ok         {0}" -f $rel)
        }
        elseif (Test-Path $skillPath) {
          Write-Host ("incomplete {0} (SKILL.md missing)" -f $rel)
          $failed = $true
        }
        else {
          Write-Host ("missing    {0}" -f $rel)
          $failed = $true
        }
      }
    }
    return (-not $failed)
  }

  function Show-RepairHint {
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "install.ps1"))) {
      $repairArgs = @("-Target `"$TargetRoot`"", "-Mode adopt")
      if ($Scope -eq "user") { $repairArgs += "-Scope user" }
      if ($RequestedAgents.Count -gt 0) { $repairArgs += ("-Agent " + ($RequestedAgents -join ",")) }
      Write-Host ("Repair: & `"{0}`" {1}" -f (Join-Path $PSScriptRoot "install.ps1"), ($repairArgs -join " "))
    }
    else {
      Write-Host ("Repair: irm https://raw.githubusercontent.com/{0}/{1}/install.ps1 -OutFile install.ps1; .\install.ps1 -Target `"{2}`" -Mode adopt" -f $Repo, $Ref, $TargetRoot)
    }
  }

  if ($Check) {
    $SkillsRoot = Join-Path $SourceRoot "skills"
    if (-not (Test-Path $SkillsRoot) -or -not (Get-ChildItem $SkillsRoot -Directory)) {
      Write-Error "No skills found in $SourceRoot; cannot verify required skills"
    }
    Write-Host "Skill check: target=$TargetRoot scope=$Scope"
    $checkFailed = $false
    if (-not (Test-RequiredSkills)) { $checkFailed = $true }
    if (Test-Path (Join-Path $TargetRoot ".harness/.rsi/policy.yaml")) {
      Write-Host "ok         .harness/.rsi/policy.yaml"
    } else {
      Write-Host "missing    .harness/.rsi/policy.yaml"
      $checkFailed = $true
    }
    $agentsMd = Join-Path $TargetRoot "AGENTS.md"
    if ((Test-Path -LiteralPath $agentsMd) -and ((Get-Content -LiteralPath $agentsMd -Raw).Contains($script:BeginMark))) {
      Write-Host "ok         AGENTS.md managed section"
    } else {
      Write-Host "missing    AGENTS.md managed section"
      $checkFailed = $true
    }
    # Legacy layout leftovers are reported, not failed.
    if (Test-Path (Join-Path $TargetRoot ".agents/skills")) { Write-Host "legacy     .agents/skills (old layout; re-run installer to migrate)" }
    if (Test-Path (Join-Path $TargetRoot ".rsi")) { Write-Host "legacy     .rsi/ (old layout; re-run installer to migrate)" }
    if (-not $checkFailed) {
      Write-Host "All required skills present."
      exit 0
    }
    Write-Host ""
    Write-Host "Missing or incomplete skills detected."
    Show-RepairHint
    exit 1
  }

  if ($Mode -eq "auto") {
    if (Test-NearEmpty) { $Mode = "init" } else { $Mode = "adopt" }
  }

  Write-Host "Project bootstrap: mode=$Mode target=$TargetRoot"

  # --- Core files ---------------------------------------------------------------
  Merge-Managed (Join-Path $TargetRoot "AGENTS.md") (Build-AgentsSection) $AgentsSkel
  Merge-Managed (Join-Path $TargetRoot "CLAUDE.md") (Build-ClaudeSection) $ClaudeSkel
  Get-ChildItem (Join-Path $SourceRoot "templates/project/docs/engineering") -Filter *.md | ForEach-Object {
    Managed-Copy $_.FullName (Join-Path $TargetRoot ("docs/engineering/" + $_.Name))
  }
  $PlatformSrc = Join-Path $SourceRoot "templates/project/docs/engineering/platform"
  if (Test-Path $PlatformSrc) {
    Get-ChildItem $PlatformSrc -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($PlatformSrc.Length).TrimStart('\', '/')
      Managed-Copy $_.FullName (Join-Path $TargetRoot ("docs/engineering/platform/" + $rel))
    }
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
      Managed-Copy $_.FullName (Join-Path $TargetRoot (".harness/.rsi/" + $rel))
    }
  }

  # Distribute the Kimi Code compact-recall hook scripts (PostCompact archive +
  # UserPromptSubmit recall). Canonical copies live in the harness repo's own
  # scripts/ directory; $SourceRoot may have been re-rooted into .harness.
  $HookSrcRoot = $SourceRoot
  if (-not (Test-Path (Join-Path $HookSrcRoot "scripts/compact-archive.sh"))) {
    $HookSrcRoot = Split-Path $SourceRoot -Parent
  }
  foreach ($name in @("compact-archive.sh", "compact-archive.ps1", "compact-archive.py",
                      "session-recall.sh", "session-recall.ps1", "session-recall.py",
                      "install-kimi-hooks.sh", "install-kimi-hooks.ps1",
                      "install-agent-hooks.py", "install-agent-hooks.sh", "install-agent-hooks.ps1",
                      "compact-recall.pi.ts", "compact-recall.opencode.ts")) {
    $src = Join-Path $HookSrcRoot "scripts/$name"
    if (Test-Path $src) { Managed-Copy $src (Join-Path $TargetRoot "scripts/$name") }
  }

  # Adapt and install compact-recall hooks for every agent selected via -Agent
  # (best effort: a failure warns but never fails the install).
  if ($Agent) {
    $requested = @()
    foreach ($item in $Agent) {
      foreach ($a in ($item -split ',')) {
        $a = $a.Trim().ToLowerInvariant()
        if (-not $a) { continue }
        if ($a -eq "all") { $requested += @("claude", "pi", "kimi", "opencode", "codex") } else { $requested += $a }
      }
    }
    $seen = @{}
    foreach ($a in $requested) {
      if ($a -eq "kimi-code") { $a = "kimi" }
      if ($a -eq "agents") { continue }
      if (@("claude", "pi", "kimi", "opencode", "codex") -notcontains $a) { continue }
      if ($seen.ContainsKey($a)) { continue }
      $seen[$a] = $true
      $py = $null
      foreach ($c in @('python', 'python3', 'py')) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $py = $cmd.Source; break }
      }
      if (-not $py) {
        Write-Host "warn: no python interpreter; skipping $a hooks"
        continue
      }
      Write-Host "hooks  $a"
      & $py (Join-Path $TargetRoot "scripts/install-agent-hooks.py") $a --target $TargetRoot --scope $Scope
      if ($LASTEXITCODE -ne 0) { Write-Host "warn: $a hook adaptation failed (non-fatal)" }
    }
  }

  Migrate-Legacy

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

  # compact-recall hook state: archived summaries + per-session recall markers.
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot "conversations/archive"), (Join-Path $TargetRoot "conversations/.state") | Out-Null

  Write-Manifest

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

# zvec (zg) local search index
.zvec-grep/

# Environment / secrets
.env
.env.*
!.env.example

# Temporary project artifacts
tmp/*
!tmp/index.md

# compact-recall per-session recall markers (local state)
conversations/.state/

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

  # --- Environment bootstrap (G6) -------------------------------------------------
  # Discovers scripts/setup-env.ps1 first; otherwise detects ecosystem manifests
  # and installs dependencies with the matching package manager. Only repository
  # evidence is used — commands are never invented. Everything is recorded in
  # .harness/reports/env-report.md. Failures warn by default; -StrictEnv
  # upgrades them to exit code 3.
  $EnvReportDir = Join-Path $TargetRoot ".harness/reports"
  $EnvReport = Join-Path $EnvReportDir "env-report.md"

  if ($SkipEnv) {
    Write-Host "skip   env bootstrap (-SkipEnv)"
  }
  else {
    Write-Host ""
    Write-Host "Environment bootstrap:"
    New-Item -ItemType Directory -Force -Path $EnvReportDir | Out-Null
    $script:EnvStatus = 0
    $script:UnknownCount = 0
    $script:EnvAnyManifest = $false
    $script:ReportBody = ""

    function Invoke-EnvNote([string]$Text) {
      Write-Host ("note   {0}" -f $Text)
      $script:ReportBody = $script:ReportBody + "`n- note: $Text"
    }

    function Invoke-EnvUnknown([string]$Text) {
      $script:UnknownCount = $script:UnknownCount + 1
      [Console]::Error.WriteLine("unknown $Text")
      $script:ReportBody = $script:ReportBody + "`n- UNKNOWN: $Text"
    }

    function Invoke-EnvCommand([string]$Label, [string[]]$Cmd) {
      $display = ($Cmd -join " ")
      if ($DryRunEnv) {
        Write-Host ("dryrun {0}: {1}" -f $Label, $display)
        $script:ReportBody = $script:ReportBody + "`n- [dry-run] ${Label}: $display"
        return
      }
      Write-Host ("run    {0}: {1}" -f $Label, $display)
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      Push-Location $TargetRoot
      try {
        $exe = $Cmd[0]
        $argList = @()
        if ($Cmd.Count -gt 1) { $argList = $Cmd[1..($Cmd.Count - 1)] }
        # Env bootstrap is warn-by-default: a native command writing to stderr
        # must not become terminating. PS 5.1 raises NativeCommandError for
        # native stderr even under redirection when EAP is Stop.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $exe @argList *> $null
        $rc = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
      }
      finally {
        Pop-Location
      }
      $sw.Stop()
      if (-not $rc) { $rc = 0 }
      $script:ReportBody = $script:ReportBody + "`n- ${Label}: $display - exit $rc ($([int]$sw.Elapsed.TotalSeconds)s)"
      if ($rc -ne 0) { $script:EnvStatus = 1 }
    }

    $SetupEnv = Join-Path $TargetRoot "scripts/setup-env.ps1"
    if (Test-Path -LiteralPath $SetupEnv) {
      Write-Host "found  scripts/setup-env.ps1"
      Invoke-EnvCommand "setup-env" @("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $SetupEnv)
    }
    else {
      Invoke-EnvNote "no scripts/setup-env.ps1; falling back to ecosystem detection"
      # Node.js
      $PkgJson = Join-Path $TargetRoot "package.json"
      if (Test-Path -LiteralPath $PkgJson) {
        $script:EnvAnyManifest = $true
        $pkg = Get-Content $PkgJson -Raw
        if ($pkg -match '"(dependencies|devDependencies)"') {
          if (Test-Path (Join-Path $TargetRoot "pnpm-lock.yaml")) {
            if (Get-Command pnpm -ErrorAction SilentlyContinue) { Invoke-EnvCommand "node (pnpm)" @("pnpm", "install", "--frozen-lockfile") } else { Invoke-EnvUnknown "pnpm not found; cannot install deps from pnpm-lock.yaml" }
          }
          elseif (Test-Path (Join-Path $TargetRoot "yarn.lock")) {
            if (Get-Command yarn -ErrorAction SilentlyContinue) { Invoke-EnvCommand "node (yarn)" @("yarn", "--frozen-lockfile") } else { Invoke-EnvUnknown "yarn not found; cannot install deps from yarn.lock" }
          }
          elseif (Test-Path (Join-Path $TargetRoot "package-lock.json")) {
            if (Get-Command npm -ErrorAction SilentlyContinue) { Invoke-EnvCommand "node (npm ci)" @("npm", "ci") } else { Invoke-EnvUnknown "npm not found; cannot install deps from package-lock.json" }
          }
          else {
            if (Get-Command npm -ErrorAction SilentlyContinue) {
              Invoke-EnvCommand "node (npm install)" @("npm", "install")
              Invoke-EnvUnknown "package.json has no lockfile; installed with npm install - review version pinning"
            }
            else {
              Invoke-EnvUnknown "npm not found; cannot install node dependencies"
            }
          }
          if (($pkg -match '"build"\s*:') -and (Get-Command npm -ErrorAction SilentlyContinue)) {
            Invoke-EnvCommand "build (npm run build)" @("npm", "run", "build")
          }
        }
        else {
          Invoke-EnvNote "package.json declares no dependencies; skipping node install"
        }
      }
      # Python (requirements.txt)
      $ReqTxt = Join-Path $TargetRoot "requirements.txt"
      if (Test-Path -LiteralPath $ReqTxt) {
        $script:EnvAnyManifest = $true
        $VenvPy = Join-Path $TargetRoot ".venv/Scripts/python.exe"
        if (Test-Path -LiteralPath $VenvPy) {
          Invoke-EnvCommand "python (.venv pip)" @($VenvPy, "-m", "pip", "install", "-r", "requirements.txt")
        }
        else {
          Invoke-EnvUnknown "requirements.txt found but no .venv; create a venv or provide scripts/setup-env.ps1 (harness will not create one)"
        }
      }
      # Python (pyproject.toml)
      $Pyproject = Join-Path $TargetRoot "pyproject.toml"
      if (Test-Path -LiteralPath $Pyproject) {
        $script:EnvAnyManifest = $true
        if (Test-Path (Join-Path $TargetRoot "poetry.lock")) {
          if (Get-Command poetry -ErrorAction SilentlyContinue) { Invoke-EnvCommand "python (poetry)" @("poetry", "install") } else { Invoke-EnvUnknown "poetry not found; cannot install deps from poetry.lock" }
        }
        elseif (Test-Path (Join-Path $TargetRoot "uv.lock")) {
          if (Get-Command uv -ErrorAction SilentlyContinue) { Invoke-EnvCommand "python (uv)" @("uv", "sync") } else { Invoke-EnvUnknown "uv not found; cannot install deps from uv.lock" }
        }
      }
      # Go / Rust / JVM / CMake
      if (Test-Path (Join-Path $TargetRoot "go.mod")) {
        $script:EnvAnyManifest = $true
        if (Get-Command go -ErrorAction SilentlyContinue) { Invoke-EnvCommand "go (mod download)" @("go", "mod", "download") } else { Invoke-EnvUnknown "go not found; cannot fetch go.mod dependencies" }
      }
      if (Test-Path (Join-Path $TargetRoot "Cargo.toml")) {
        $script:EnvAnyManifest = $true
        if (Get-Command cargo -ErrorAction SilentlyContinue) { Invoke-EnvCommand "rust (cargo fetch)" @("cargo", "fetch") } else { Invoke-EnvUnknown "cargo not found; cannot fetch Cargo.toml dependencies" }
      }
      if (Test-Path (Join-Path $TargetRoot "pom.xml")) {
        $script:EnvAnyManifest = $true
        if (Test-Path (Join-Path $TargetRoot "mvnw.cmd")) {
          Invoke-EnvCommand "maven (mvnw)" @(".\mvnw.cmd", "-B", "-q", "-DskipTests", "dependency:resolve")
        }
        elseif (Get-Command mvn -ErrorAction SilentlyContinue) {
          Invoke-EnvCommand "maven (mvn)" @("mvn", "-B", "-q", "-DskipTests", "dependency:resolve")
        }
        else {
          Invoke-EnvUnknown "maven not found and no mvnw wrapper; cannot resolve pom.xml dependencies"
        }
      }
      if ((Test-Path (Join-Path $TargetRoot "build.gradle")) -or (Test-Path (Join-Path $TargetRoot "build.gradle.kts"))) {
        $script:EnvAnyManifest = $true
        if (Test-Path (Join-Path $TargetRoot "gradlew.bat")) {
          Invoke-EnvCommand "gradle (gradlew)" @(".\gradlew.bat", "dependencies")
        }
        elseif (Get-Command gradle -ErrorAction SilentlyContinue) {
          Invoke-EnvCommand "gradle" @("gradle", "dependencies")
        }
        else {
          Invoke-EnvUnknown "gradle not found and no gradlew wrapper; cannot resolve gradle dependencies"
        }
      }
      if (Test-Path (Join-Path $TargetRoot "CMakeLists.txt")) {
        $script:EnvAnyManifest = $true
        if ((Test-Path (Join-Path $TargetRoot "vcpkg.json")) -or (Test-Path (Join-Path $TargetRoot "conanfile.txt")) -or (Test-Path (Join-Path $TargetRoot "conanfile.py"))) {
          Invoke-EnvUnknown "CMakeLists.txt found with vcpkg/conan manifests; toolchain choice needs human input (provide scripts/setup-env.ps1)"
        }
        elseif (Get-Command cmake -ErrorAction SilentlyContinue) {
          Invoke-EnvCommand "cmake (configure)" @("cmake", "-S", ".", "-B", "build")
        }
        else {
          Invoke-EnvUnknown "cmake not found; cannot configure CMakeLists.txt"
        }
      }
      if ($script:EnvAnyManifest -eq $false) {
        Invoke-EnvNote "no dependency manifests detected (package.json / requirements.txt / go.mod etc.)"
      }
    }

    # Workspace search provisioning (zvec/zg) - on by default via -Search zvec.
    # The CLI is installed when missing (npm channel); the index itself is
    # deferred to the first fuzzy search per the AGENTS.md search routing.
    if ($Search -eq "zvec") {
      # Windows reality: npm shims differ per shell and a sh wrapper on PATH is
      # not PS-executable, so probe PS-native executables first, then Git Bash,
      # and only fall back to npm provisioning when both fail.
      $zgOk = $false
      $zgVer = ""
      $zgVia = ""
      foreach ($name in @("zg.cmd", "zg.exe")) {
        if ($zgOk) { break }
        $c = Get-Command $name -ErrorAction SilentlyContinue
        if ($c) {
          $prevEap = $ErrorActionPreference
          $ErrorActionPreference = "Continue"
          try {
            # Capture fully, then select: Select-Object -First 1 in-pipeline
            # terminates the native command and corrupts $LASTEXITCODE.
            $zgOut = & $c.Source version 2>$null
            if ($LASTEXITCODE -eq 0 -and $zgOut) { $zgOk = $true; $zgVer = [string]($zgOut | Select-Object -First 1); $zgVia = $c.Source }
          } catch { $zgOk = $false } finally { $ErrorActionPreference = $prevEap }
        }
      }
      if (-not $zgOk) {
        $bashCmd = Get-Command bash -ErrorAction SilentlyContinue
        if ($bashCmd) {
          $prevEap = $ErrorActionPreference
          $ErrorActionPreference = "Continue"
          try {
            # -i so .bashrc (which typically adds ~/.local/bin to PATH) loads;
            # job-control warnings go to stderr and are discarded here.
            $zgOut = & bash -lic "zg version 2>/dev/null" 2>$null
            if ($LASTEXITCODE -eq 0 -and $zgOut) { $zgOk = $true; $zgVer = [string]($zgOut | Select-Object -First 1); $zgVia = "Git Bash" }
          } catch { $zgOk = $false } finally { $ErrorActionPreference = $prevEap }
        }
      }
      if ($zgOk) {
        $via = if ($zgVia) { " via $zgVia" } else { "" }
        Invoke-EnvNote "zvec (zg $zgVer$via) available; index builds on first fuzzy search (see AGENTS.md search routing)"
      }
      elseif (Get-Command npm -ErrorAction SilentlyContinue) {
        # cmd /c keeps npm's noisy stderr (deprecation warnings) out of the
        # PowerShell stream machinery (PS 5.1 turns it into NativeCommandError).
        Invoke-EnvCommand "zvec install (npm -g @zvec/zvec-grep)" @("cmd", "/c", "npm", "install", "-g", "@zvec/zvec-grep")
        # Recheck by EXECUTION, not mere presence: an interrupted install can
        # leave a shim on PATH that cannot run (seen 2026-09-20).
        $zgRecheck = $false
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
          $null = (zg version 2>$null | Select-Object -First 1)
          if ($LASTEXITCODE -eq 0) { $zgRecheck = $true }
        }
        catch { $zgRecheck = $false }
        finally { $ErrorActionPreference = $prevEap }
        if ($zgRecheck) {
          Invoke-EnvNote "zvec installed; index builds on first fuzzy search (see AGENTS.md search routing)"
        }
        else {
          Invoke-EnvUnknown "zvec install ran but zg is still not executable; check the npm global bin directory"
        }
      }
      else {
        Invoke-EnvUnknown "zvec (zg) not found and npm unavailable; install @zvec/zvec-grep to enable the default fuzzy-search layer"
      }
    }

    $reportResult = "ok"
    if ($script:EnvStatus -eq 1) { $reportResult = "failed" }
    $reportMode = "apply"
    if ($DryRunEnv) { $reportMode = "dry-run" }
    $reportLines = @(
      "# Environment Bootstrap Report",
      "",
      "- date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
      "- target: $TargetRoot",
      "- mode: $reportMode",
      "- result: $reportResult",
      "- unknown_count: $($script:UnknownCount)",
      "",
      "## Actions"
    )
    if ($script:ReportBody) {
      $reportLines += ($script:ReportBody -split "`n" | Where-Object { $_ -ne "" })
    }
    [System.IO.File]::WriteAllText($EnvReport, ($reportLines -join [System.Environment]::NewLine) + [System.Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("report {0}" -f (Get-RelPath $EnvReport))

    if ($StrictEnv -and $script:EnvStatus -eq 1) {
      [Console]::Error.WriteLine("strict-env: environment bootstrap failed")
      exit 3
    }
  }

  Write-Host ""
  Write-Host "Bootstrap complete."
  Write-Host "Next: fill docs/engineering/index.md and only the rule files relevant to this project."
  Write-Host "Agent entry: AGENTS.md (managed section) + CLAUDE.md"
  Write-Host "Mechanism: .harness/ (skills, policy, manifest, reports)"
  if (-not $NoSkill) {
    Write-Host ""
    Write-Host "Required skills:"
    if (-not (Test-RequiredSkills)) {
      Write-Warning "some skills are still missing; re-run the installer to repair"
    }
  }

  # Explicit success exit: without this, powershell -File leaks the last
  # native command's exit code (e.g. a failed env bootstrap helper).
  exit 0
}
finally {
  if ($TmpRoot -and (Test-Path $TmpRoot)) {
    Remove-Item -Recurse -Force $TmpRoot -ErrorAction SilentlyContinue
  }
}
