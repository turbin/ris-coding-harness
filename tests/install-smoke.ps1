#!/usr/bin/env pwsh
#requires -Version 5.1
# Smoke test for install.ps1 — Windows counterpart of tests/install-smoke.sh.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# The installer distributes the skills marked scope=user in
# .harness/skill-scope.txt into the agent user directories under the user home,
# so this test re-launches itself in a child process with an isolated
# USERPROFILE/HOME: PowerShell binds $HOME at process start, which means the
# variables must be set before the process that runs install.ps1 begins. The
# real user profile is never touched. The child runs the test body below.
if ($env:RIS_SMOKE_ISOLATED -ne "1") {
  $IsoHome = Join-Path ([System.IO.Path]::GetTempPath()) ("ris-smoke-home-" + [System.Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $IsoHome | Out-Null
  # Run from the isolated home: PowerShell resolves profile-derived caches
  # (Microsoft\Windows\PowerShell\ModuleAnalysisCache) relative to the current
  # directory when the overridden profile cannot be resolved, and that must not
  # litter the repository working tree.
  Set-Location -LiteralPath $IsoHome
  $env:RIS_SMOKE_ISOLATED = "1"
  $env:USERPROFILE = $IsoHome
  $env:HOME = $IsoHome
  $env:KIMI_CODE_HOME = Join-Path $IsoHome ".kimi-code"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
  $ChildRc = $LASTEXITCODE
  Remove-Item -Recurse -Force $IsoHome -ErrorAction SilentlyContinue
  exit $ChildRc
}

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

  # Empty project should receive canonical init layout under .harness/.
  Assert-True (Test-Path (Join-Path $New "AGENTS.md")) "new/AGENTS.md"
  Assert-True (Test-Path (Join-Path $New "CLAUDE.md")) "new/CLAUDE.md"
  Assert-True ((Get-Content (Join-Path $New "AGENTS.md") -Raw) -match "ris-coding-harness:begin") "AGENTS managed markers"
  Assert-True ((Get-Content (Join-Path $New "CLAUDE.md") -Raw) -match "ris-coding-harness:begin") "CLAUDE managed markers"
  Assert-True (Test-Path (Join-Path $New "src/index.md")) "new/src/index.md"
  # Layout v2: every installer-managed record directory lives under .harness/.
  Assert-True (Test-Path (Join-Path $New ".harness/docs/engineering/index.md")) "new rules index"
  Assert-True (Test-Path (Join-Path $New ".harness/docs/engineering/platform/index.md")) "new platform index"
  Assert-True (Test-Path (Join-Path $New ".harness/decisions/index.md")) "new decisions index"
  Assert-True (Test-Path (Join-Path $New ".harness/issues/index.md")) "new issues index"
  Assert-True (Test-Path (Join-Path $New ".harness/progress/index.md")) "new progress index"
  Assert-True (Test-Path (Join-Path $New ".harness/conversations/archive")) "new conversations archive"
  Assert-True (Test-Path (Join-Path $New ".harness/conversations/.state")) "new conversations state"
  Assert-True ((Get-Content (Join-Path $New ".harness/layout-version.txt") -Raw).Trim() -eq "2") "layout marker v2"
  # Root level keeps only project workspace: no installer-managed record dirs.
  foreach ($rel in @("docs/engineering", "decisions", "issues", "progress", "conversations", "evals")) {
    Assert-True (-not (Test-Path (Join-Path $New $rel))) "root must not hold $rel (layout v2)"
  }
  Assert-True (Test-Path (Join-Path $New ".harness/skills/pm-workers-engineering/SKILL.md")) "new skill"
  Assert-True (Test-Path (Join-Path $New ".harness/skills/rsi-loop/SKILL.md")) "new rsi-loop"
  Assert-True (Test-Path (Join-Path $New ".harness/skills/rsi-loop/references/preflight.md")) "new rsi-loop preflight"
  Assert-True (Test-Path (Join-Path $New ".harness/.rsi/policy.yaml")) "new policy"
  Assert-True (Test-Path (Join-Path $New ".harness/manifest.json")) "new manifest"
  # Hook script copies are harness mechanism (G1): they land under
  # .harness/scripts/, never in the project-owned root scripts/.
  Assert-True (Test-Path (Join-Path $New ".harness/scripts/compact-archive.py")) "new .harness/scripts archive"
  Assert-True (Test-Path (Join-Path $New ".harness/scripts/session-recall.py")) "new .harness/scripts recall"
  Assert-True (Test-Path (Join-Path $New ".harness/scripts/install-agent-hooks.py")) "new .harness/scripts hook installer"
  Assert-True (-not (Test-Path (Join-Path $New "scripts/compact-archive.py"))) "root scripts must not hold hook copies"
  Assert-True (-not (Test-Path (Join-Path $New "scripts/session-recall.py"))) "root scripts must not hold hook copies"
  Assert-True (-not (Test-Path (Join-Path $New "scripts/install-agent-hooks.py"))) "root scripts must not hold hook copies"
  Assert-True ((Get-Content (Join-Path $New ".harness/manifest.json") -Raw) -match '"sha256"') "manifest hashes"
  # Manifest records the two scopes: project skills, user skills, and where the
  # user-level ones landed (absolute paths outside the target).
  $manifest = Get-Content (Join-Path $New ".harness/manifest.json") -Raw
  Assert-True ($manifest -notmatch '"skills":\s*\[[^]]*c4-architecture') "user-level skill must not be listed as a project skill"
  Assert-True ($manifest -match '"user_skills":\s*\[[^]]*"architecture-topology"') "manifest user_skills: architecture-topology"
  Assert-True ($manifest -match '"user_skills":\s*\[[^]]*"c4-architecture"') "manifest user_skills: c4-architecture"
  Assert-True ($manifest -match '"user_skills":\s*\[[^]]*"mermaid-diagrams"') "manifest user_skills: mermaid-diagrams"
  Assert-True ($manifest -match '"skill_scope":\s*\{[^}]*"c4-architecture":\s*"user"') "manifest skill_scope"
  Assert-True ($manifest -match '"user_agent_destinations"') "manifest user destinations"
  Assert-True ($manifest -match "\.kimi-code") "manifest kimi-code destination"
  Assert-True ($manifest -match '"layout_version":\s*2') "manifest layout version"
  Assert-True (Test-Path (Join-Path $New ".harness/evals/results")) "new evals/results"

  # Both vendored diagram skills are user-level (.harness/skill-scope.txt): they
  # land in the agent user directories and never inside the project.
  Assert-True (-not (Test-Path (Join-Path $New ".harness/skills/c4-architecture"))) "c4-architecture stays out of .harness/skills"
  Assert-True (-not (Test-Path (Join-Path $New ".harness/skills/mermaid-diagrams"))) "mermaid-diagrams stays out of .harness/skills"
  foreach ($rel in @(".claude/skills", ".pi/agent/skills", ".kimi-code/skills", ".config/opencode/skills", ".codex/skills", ".agents/skills")) {
    Assert-True (Test-Path (Join-Path $HOME "$rel/c4-architecture/SKILL.md")) "user c4-architecture in $rel"
    Assert-True (Test-Path (Join-Path $HOME "$rel/mermaid-diagrams/SKILL.md")) "user mermaid-diagrams in $rel"
  }
  Assert-True (-not (Test-Path (Join-Path $HOME ".kimi"))) "retired ~/.kimi is not used"
  $agentsMd = Get-Content (Join-Path $New "AGENTS.md") -Raw
  Assert-True ($agentsMd -match "User-level skills") "managed section marks user-level skills"
  Assert-True ($agentsMd -match "\.kimi-code/skills/c4-architecture/") "managed section names the kimi-code home"
  Assert-True ($agentsMd -match "\.claude/skills/mermaid-diagrams/") "managed section names the claude home"

  # Existing project should be adopted without canonical source/test directories.
  Assert-True (Test-Path (Join-Path $Existing "AGENTS.md")) "existing/AGENTS.md"
  Assert-True (Test-Path (Join-Path $Existing ".harness/docs/engineering/index.md")) "existing rules index"
  Assert-True (Test-Path (Join-Path $Existing ".harness/skills/pm-workers-engineering/SKILL.md")) "existing skill"
  Assert-True (-not (Test-Path (Join-Path $Existing "src"))) "existing must not get src/"
  Assert-True (-not (Test-Path (Join-Path $Existing "tests"))) "existing must not get tests/"
  Assert-True (Test-Path (Join-Path $Existing "package.json")) "package.json preserved"

  # An existing AGENTS.md is merged: user content kept, managed section appended,
  # and a re-run refreshes the section without duplicating markers.
  [System.IO.File]::WriteAllText((Join-Path $Existing "AGENTS.md"), "# our own rules`ndo not touch`n")
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode adopt -NoGit | Out-Null
  Assert-True ((Get-Content (Join-Path $Existing "AGENTS.md") -Raw) -match "do not touch") "user content kept"
  Assert-True ((Get-Content (Join-Path $Existing "AGENTS.md") -Raw) -match "ris-coding-harness:begin") "managed section appended"
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode adopt -NoGit | Out-Null
  $beginCount = ([regex]::Matches((Get-Content (Join-Path $Existing "AGENTS.md") -Raw), "ris-coding-harness:begin")).Count
  Assert-True ($beginCount -eq 1) "managed section not duplicated"
  Assert-True ((Get-Content (Join-Path $Existing "AGENTS.md") -Raw) -match "do not touch") "user content still kept"

  # Re-running must be non-destructive without -Force.
  [System.IO.File]::WriteAllText((Join-Path $Existing ".harness/docs/engineering/coding.md"), "# local customization`n")
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode adopt -NoGit | Out-Null
  $coding = Get-Content (Join-Path $Existing ".harness/docs/engineering/coding.md") -Raw
  Assert-True ($coding -match "^# local customization") "local customization preserved"

  # -Agent claude,opencode,codex installs the project skills to .harness plus all
  # three agent dirs; user-level skills stay in the user directories.
  $Multi = Join-Path $Tmp "multi"
  New-Item -ItemType Directory -Force -Path $Multi | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Multi -Mode adopt -NoGit -Agent claude,opencode,codex | Out-Null
  Assert-True (Test-Path (Join-Path $Multi ".harness/skills/pm-workers-engineering/SKILL.md")) "multi .harness skill"
  Assert-True (Test-Path (Join-Path $Multi ".claude/skills/pm-workers-engineering/SKILL.md")) "multi .claude skill"
  Assert-True (Test-Path (Join-Path $Multi ".opencode/skills/pm-workers-engineering/SKILL.md")) "multi .opencode skill"
  Assert-True (Test-Path (Join-Path $Multi ".codex/skills/pm-workers-engineering/SKILL.md")) "multi .codex skill"
  Assert-True (-not (Test-Path (Join-Path $Multi ".claude/skills/c4-architecture"))) "user-level skill stays out of .claude/skills"
  Assert-True (-not (Test-Path (Join-Path $Multi ".opencode/skills/mermaid-diagrams"))) "user-level skill stays out of .opencode/skills"
  Assert-True (-not (Test-Path (Join-Path $Multi ".codex/skills/c4-architecture"))) "user-level skill stays out of .codex/skills"

  # -Agent accepts multiple names as an array (repeated parameters cannot bind).
  $Repeat = Join-Path $Tmp "repeat"
  New-Item -ItemType Directory -Force -Path $Repeat | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Repeat -Mode adopt -NoGit -Agent claude,pi | Out-Null
  Assert-True (Test-Path (Join-Path $Repeat ".pi/skills/pm-workers-engineering/SKILL.md")) "repeat .pi skill"
  Assert-True (Test-Path (Join-Path $Repeat ".claude/skills/pm-workers-engineering/SKILL.md")) "repeat .claude skill"

  # Unknown agent must fail with exit code 2.
  $Bad = Join-Path $Tmp "bad"
  New-Item -ItemType Directory -Force -Path $Bad | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Bad -Mode adopt -NoGit -Agent foo | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "unknown agent must exit 2"
  Assert-True (-not (Test-Path (Join-Path $Bad "AGENTS.md"))) "unknown agent must abort before installing"

  # -Check on an absent target must report missing skills, exit 1, and write nothing.
  $CheckAbsent = Join-Path $Tmp "check-absent"
  $checkOut = & (Join-Path $Root "install.ps1") -Target $CheckAbsent -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 1) "-Check on absent target must exit 1"
  Assert-True (($checkOut -join "`n") -match "missing") "absent target must report missing skills"
  Assert-True (-not (Test-Path $CheckAbsent)) "-Check must not create the target"

  # -Check covers skills, policy, and the AGENTS.md managed section, and reports
  # the user-level copies in the agent user directories.
  $checkOut = & (Join-Path $Root "install.ps1") -Target $New -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 0) "-Check must pass after install"
  Assert-True (($checkOut -join "`n") -match "\.harness/.rsi/policy\.yaml") "policy check line"
  Assert-True (($checkOut -join "`n") -match "AGENTS\.md managed section") "managed section check line"
  Assert-True (($checkOut -join "`n") -match [regex]::Escape((Join-Path $HOME ".kimi-code/skills/c4-architecture"))) "user-level c4 check line"
  Assert-True (($checkOut -join "`n") -match [regex]::Escape((Join-Path $HOME ".claude/skills/mermaid-diagrams"))) "user-level mermaid check line"

  # -Check -Agent flags a destination that was never installed.
  $checkOut = & (Join-Path $Root "install.ps1") -Target $New -Check -Agent claude 6>&1
  Assert-True ($LASTEXITCODE -eq 1) "-Check -Agent claude must exit 1"
  Assert-True (($checkOut -join "`n") -match "\.claude") "claude destination must be reported missing"

  # An incomplete skill (SKILL.md deleted) is detected, then healed by re-running.
  Remove-Item (Join-Path $Existing ".harness/skills/rsi-loop/SKILL.md") -Force
  $checkOut = & (Join-Path $Root "install.ps1") -Target $Existing -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 1) "-Check must detect incomplete skill"
  Assert-True (($checkOut -join "`n") -match "incomplete") "incomplete skill must be reported"
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode adopt -NoGit | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Existing -Check | Out-Null
  Assert-True ($LASTEXITCODE -eq 0) "-Check must pass after repair"
  $coding = Get-Content (Join-Path $Existing ".harness/docs/engineering/coding.md") -Raw
  Assert-True ($coding -match "^# local customization") "local customization preserved"

  # A deleted user-level copy is detected and healed by a re-run.
  Remove-Item (Join-Path $HOME ".codex/skills/c4-architecture/SKILL.md") -Force
  $checkOut = & (Join-Path $Root "install.ps1") -Target $New -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 1) "-Check must detect an incomplete user-level skill"
  Assert-True (($checkOut -join "`n") -match "incomplete .*codex.*c4-architecture") "incomplete user-level skill reported"
  & (Join-Path $Root "install.ps1") -Target $New -Mode adopt -NoGit | Out-Null
  Assert-True (Test-Path (Join-Path $HOME ".codex/skills/c4-architecture/SKILL.md")) "user-level skill healed"
  Assert-True (-not (Test-Path (Join-Path $New ".harness/skills/c4-architecture"))) "healing stays out of the project"

  # A user-level copy that is absent entirely is reported missing (exit 1).
  Move-Item (Join-Path $HOME ".agents/skills/mermaid-diagrams") (Join-Path $HOME "mermaid-diagrams-away")
  $checkOut = & (Join-Path $Root "install.ps1") -Target $New -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 1) "-Check must detect a missing user-level skill"
  Assert-True (($checkOut -join "`n") -match "missing .*agents.*mermaid-diagrams") "missing user-level skill reported"
  & (Join-Path $Root "install.ps1") -Target $New -Mode adopt -NoGit | Out-Null
  Assert-True (Test-Path (Join-Path $HOME ".agents/skills/mermaid-diagrams/SKILL.md")) "missing user-level skill restored"
  Assert-True (-not (Test-Path (Join-Path $New ".harness/skills/mermaid-diagrams"))) "restore stays out of the project"

  # -Scope user installs every skill under the (isolated) user home and uses the
  # Kimi Code home for kimi/kimi-code, never the retired ~/.kimi.
  $UserProj = Join-Path $Tmp "userproj"
  New-Item -ItemType Directory -Force -Path $UserProj | Out-Null
  & (Join-Path $Root "install.ps1") -Target $UserProj -Mode adopt -NoGit -Scope user -Agent claude,kimi-code -SkipEnv | Out-Null
  Assert-True ($LASTEXITCODE -eq 0) "-Scope user install succeeds"
  Assert-True (Test-Path (Join-Path $HOME ".claude/skills/pm-workers-engineering/SKILL.md")) "user-scope claude skill"
  Assert-True (Test-Path (Join-Path $HOME ".kimi-code/skills/pm-workers-engineering/SKILL.md")) "user-scope kimi-code skill"
  Assert-True (Test-Path (Join-Path $HOME ".kimi-code/skills/c4-architecture/SKILL.md")) "user-scope kimi-code c4 skill"
  Assert-True (-not (Test-Path (Join-Path $HOME ".kimi/skills"))) "user-scope must not write the retired ~/.kimi"
  Assert-True (-not (Test-Path (Join-Path $UserProj ".claude"))) "user-scope leaves no project agent dir"

  # -Check and -NoSkill are mutually exclusive.
  & (Join-Path $Root "install.ps1") -Target $New -Check -NoSkill 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "-Check -NoSkill must exit 2"

  # Exit code contract: invalid mode / unknown option must exit 2.
  & (Join-Path $Root "install.ps1") -Target $New -Mode bogus -NoGit 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "-Mode bogus must exit 2"
  & (Join-Path $Root "install.ps1") -Target $New --bogus-flag 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "unknown option must exit 2"

  # -Agent names are case-insensitive.
  $Upper = Join-Path $Tmp "upper"
  New-Item -ItemType Directory -Force -Path $Upper | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Upper -Mode adopt -NoGit -Agent CLAUDE | Out-Null
  Assert-True (Test-Path (Join-Path $Upper ".claude/skills/pm-workers-engineering/SKILL.md")) "uppercase agent name works"

  # .gitignore template parity: Thumbs.db present.
  Assert-True ((Get-Content (Join-Path $New ".gitignore") -Raw) -match "Thumbs\.db") "gitignore Thumbs.db"

  # Search routing (default -Search zvec): AGENTS section carries the routing
  # block; env report mentions zvec; no eager index is built at install time.
  Assert-True ((Get-Content (Join-Path $New "AGENTS.md") -Raw) -match "zvec is the default fuzzy-search layer") "agents search routing"
  Assert-True ((Get-Content (Join-Path $New ".harness/reports/env-report.md") -Raw) -match "zvec") "env report mentions zvec"
  Assert-True (-not (Test-Path (Join-Path $New ".zvec-grep"))) "no eager zvec index at install time"
  Assert-True ((Get-Content (Join-Path $New ".gitignore") -Raw) -match "\.zvec-grep/") "gitignore zvec store"

  # -Search off: managed section and env report stay zvec-free.
  $SearchOff = Join-Path $Tmp "searchoff"
  & (Join-Path $Root "install.ps1") -Target $SearchOff -Mode adopt -NoGit -Search off | Out-Null
  Assert-True ($LASTEXITCODE -eq 0) "-Search off installs"
  $offAgents = Get-Content (Join-Path $SearchOff "AGENTS.md") -Raw
  Assert-True ($offAgents -match "ris-coding-harness:begin") "off case keeps managed section"
  Assert-True ($offAgents -notmatch "zvec") "-Search off omits routing"
  Assert-True ((Get-Content (Join-Path $SearchOff ".harness/reports/env-report.md") -Raw) -notmatch "zvec") "-Search off skips zvec env stage"

  # Invalid -Search value exits 2.
  & (Join-Path $Root "install.ps1") -Target (Join-Path $Tmp "sbad") -Mode adopt -NoGit -Search bogus 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "-Search bogus must exit 2"

  # -Search off skips the routing block, graphify included, but the manifest
  # still records the graphify decision. The word "graphify" itself may still
  # appear in the user-level skills blurbs, so assert on the routing lines.
  Assert-True ((Get-Content (Join-Path $SearchOff ".harness/manifest.json") -Raw) -match '"graphify"') "-Search off still records graphify in the manifest"
  Assert-True ((Get-Content (Join-Path $SearchOff "AGENTS.md") -Raw) -notmatch 'graphify is (enabled|\*\*DISABLED)') "-Search off omits the graphify routing"

  # graphify scale gate: the threshold lives in the repository-level
  # .harness/graphify-threshold.txt, and the decision reaches the managed routing
  # section and the manifest.
  $GfySmall = Join-Path $Tmp "gfy-small"
  New-Item -ItemType Directory -Force -Path $GfySmall | Out-Null
  & (Join-Path $Root "install.ps1") -Target $GfySmall -Mode adopt -NoGit -SkipEnv | Out-Null
  Assert-True ((Get-Content (Join-Path $GfySmall "AGENTS.md") -Raw) -match "- graphify is enabled for this project \(0 files <= threshold 483\)") "graphify on routing"
  $gfyManifest = Get-Content (Join-Path $GfySmall ".harness/manifest.json") -Raw
  Assert-True ($gfyManifest -match '"graphify":\s*\{[^}]*"decision":\s*"on"') "manifest graphify on"
  Assert-True ($gfyManifest -match '"graphify":\s*\{[^}]*"metric":\s*"files"') "manifest graphify metric"
  Assert-True ($gfyManifest -match '"graphify":\s*\{[^}]*"value":\s*0') "manifest graphify value"
  Assert-True ($gfyManifest -match '"graphify":\s*\{[^}]*"threshold":\s*483') "manifest graphify threshold"
  Assert-True ($gfyManifest -match '"graphify":\s*\{[^}]*"source":\s*"auto"') "manifest graphify source"

  # A project above the threshold gets the explicit disable instead of the
  # graphify routing line.
  $GfyBig = Join-Path $Tmp "gfy-big"
  New-Item -ItemType Directory -Force -Path (Join-Path $GfyBig "data") | Out-Null
  foreach ($i in 1..500) { [System.IO.File]::WriteAllText((Join-Path $GfyBig "data/f$i.txt"), "") }
  & (Join-Path $Root "install.ps1") -Target $GfyBig -Mode adopt -NoGit -SkipEnv | Out-Null
  $bigAgents = Get-Content (Join-Path $GfyBig "AGENTS.md") -Raw
  Assert-True ($bigAgents -match "\(500 files > threshold 483\)") "off routing states the measured count"
  Assert-True ($bigAgents -match "graphify is \*\*DISABLED\*\* for this project") "off routing text"
  Assert-True ($bigAgents -notmatch 'graphify` when `graphify-out/') "off decision drops the graphify routing line"
  $bigManifest = Get-Content (Join-Path $GfyBig ".harness/manifest.json") -Raw
  Assert-True ($bigManifest -match '"decision":\s*"off"') "manifest graphify off"
  Assert-True ($bigManifest -match '"value":\s*500') "manifest off value"

  # A `git init`ed project with an empty index must not recount as 0 files — that
  # flipped the decision back to "on" on every re-run.
  if (Get-Command git -ErrorAction SilentlyContinue) {
    $GfyGit = Join-Path $Tmp "gfy-git"
    New-Item -ItemType Directory -Force -Path $GfyGit | Out-Null
    foreach ($i in 1..500) { [System.IO.File]::WriteAllText((Join-Path $GfyGit "f$i.txt"), "") }
    & git -C $GfyGit init -q | Out-Null
    & (Join-Path $Root "install.ps1") -Target $GfyGit -Mode adopt -NoGit -SkipEnv | Out-Null
    $gitOut = & (Join-Path $Root "install.ps1") -Target $GfyGit -Mode adopt -NoGit -SkipEnv 6>&1
    Assert-True (($gitOut -join "`n") -match "graphify off \(\d+ files > 483\)") "git project with empty index keeps the off decision"
  }

  # -Graphify on|off forces the decision over the measured file count.
  $gfyOut = & (Join-Path $Root "install.ps1") -Target $GfyBig -Mode adopt -NoGit -SkipEnv -Graphify on 6>&1
  Assert-True (($gfyOut -join "`n") -match "graphify on \(") "-Graphify on overrides the measured count"
  $bigAgents = Get-Content (Join-Path $GfyBig "AGENTS.md") -Raw
  Assert-True ($bigAgents -match "graphify is enabled for this project \(\d+ files > threshold 483; forced by -Graphify on\)") "-Graphify on injects the forced enable line"
  Assert-True ($bigAgents -notmatch "\*\*DISABLED\*\*") "-Graphify on replaces the disable text"
  $bigManifest = Get-Content (Join-Path $GfyBig ".harness/manifest.json") -Raw
  Assert-True ($bigManifest -match '"decision":\s*"on"') "forced-on decision recorded"
  Assert-True ($bigManifest -match '"source":\s*"flag"') "forced decision is recorded as flag"
  & (Join-Path $Root "install.ps1") -Target $GfySmall -Mode adopt -NoGit -SkipEnv -Graphify off | Out-Null
  $smallAgents = Get-Content (Join-Path $GfySmall "AGENTS.md") -Raw
  Assert-True ($smallAgents -match "graphify is \*\*DISABLED\*\* for this project") "-Graphify off injects the disable text"
  Assert-True ((Get-Content (Join-Path $GfySmall ".harness/manifest.json") -Raw) -match '"decision":\s*"off"') "forced-off decision recorded"

  # Invalid -Graphify value exits 2 before anything is written.
  $GfyBad = Join-Path $Tmp "gfy-bad"
  & (Join-Path $Root "install.ps1") -Target $GfyBad -Mode adopt -NoGit -Graphify maybe 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 2) "-Graphify maybe must exit 2"
  Assert-True (-not (Test-Path (Join-Path $GfyBad "AGENTS.md"))) "-Graphify maybe must abort before installing"

  # The threshold file drives the gate: a source tree carrying a tiny threshold
  # flips a small project off, and a missing file falls back to the built-in
  # default with a warning.
  $SrcCopy = Join-Path $Tmp "srccopy"
  New-Item -ItemType Directory -Force -Path $SrcCopy | Out-Null
  Copy-Item (Join-Path $Root "install.ps1") (Join-Path $SrcCopy "install.ps1")
  Copy-Item (Join-Path $Root ".harness") (Join-Path $SrcCopy ".harness") -Recurse
  [System.IO.File]::WriteAllText((Join-Path $SrcCopy ".harness/graphify-threshold.txt"), "metric: files`nthreshold: 2`n")
  $GfyThr = Join-Path $Tmp "gfy-thr"
  New-Item -ItemType Directory -Force -Path $GfyThr | Out-Null
  foreach ($n in @("a", "b", "c")) { [System.IO.File]::WriteAllText((Join-Path $GfyThr "$n.txt"), "x") }
  $thrOut = & (Join-Path $SrcCopy "install.ps1") -Target $GfyThr -Mode adopt -NoGit -SkipEnv 6>&1
  Assert-True (($thrOut -join "`n") -match "graphify off \(3 files > 2\)") "threshold file drives the gate"
  Assert-True ((Get-Content (Join-Path $GfyThr ".harness/manifest.json") -Raw) -match '"threshold":\s*2') "manifest records the file threshold"
  Remove-Item (Join-Path $SrcCopy ".harness/graphify-threshold.txt") -Force
  # [Console]::Error is process stderr, so the warning line is captured by
  # launching the installer as a child process.
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $thrWarn = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SrcCopy "install.ps1") -Target $GfyThr -Mode adopt -NoGit -SkipEnv 2>&1
  }
  finally { $ErrorActionPreference = $prevEap }
  Assert-True (($thrWarn -join "`n") -match "graphify-threshold.txt missing or invalid") "missing threshold file warns"
  Assert-True ((Get-Content (Join-Path $GfyThr ".harness/manifest.json") -Raw) -match '"threshold":\s*483') "fallback threshold"

  # Env bootstrap: fresh install without manifests records an ok report.
  Assert-True ((Get-Content (Join-Path $New ".harness/reports/env-report.md") -Raw) -match "result: ok") "env report ok after fresh install"

  # Env bootstrap: dry-run records setup-env without executing it.
  $EnvTest = Join-Path $Tmp "envtest"
  New-Item -ItemType Directory -Force -Path (Join-Path $EnvTest "scripts") | Out-Null
  $setupScript = @'
$marker = Join-Path $PSScriptRoot "../.setup-marker"
if (-not (Test-Path $marker)) { New-Item -ItemType File -Path $marker -Force | Out-Null }
exit 0
'@
  [System.IO.File]::WriteAllText((Join-Path $EnvTest "scripts/setup-env.ps1"), $setupScript)
  & (Join-Path $Root "install.ps1") -Target $EnvTest -Mode adopt -NoGit -DryRunEnv | Out-Null
  Assert-True (Test-Path (Join-Path $EnvTest ".harness/reports/env-report.md")) "env report created"
  Assert-True ((Get-Content (Join-Path $EnvTest ".harness/reports/env-report.md") -Raw) -match "\[dry-run\] setup-env") "dry-run recorded"
  Assert-True (-not (Test-Path (Join-Path $EnvTest ".setup-marker"))) "dry-run must not execute setup-env"

  # Env bootstrap: failing setup-env warns by default (exit 0, report failed).
  [System.IO.File]::WriteAllText((Join-Path $EnvTest "scripts/setup-env.ps1"), "exit 7")
  & (Join-Path $Root "install.ps1") -Target $EnvTest -Mode adopt -NoGit 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 0) "env failure warns by default"
  Assert-True ((Get-Content (Join-Path $EnvTest ".harness/reports/env-report.md") -Raw) -match "result: failed") "failing setup-env reported"

  # Env bootstrap: -StrictEnv upgrades failure to exit code 3.
  & (Join-Path $Root "install.ps1") -Target $EnvTest -Mode adopt -NoGit -StrictEnv 2>&1 | Out-Null
  Assert-True ($LASTEXITCODE -eq 3) "-StrictEnv must exit 3 on failure"

  # Env bootstrap: -SkipEnv writes no env report (.harness/ itself belongs to the mechanism layer).
  $EnvSkip = Join-Path $Tmp "envskip"
  New-Item -ItemType Directory -Force -Path $EnvSkip | Out-Null
  & (Join-Path $Root "install.ps1") -Target $EnvSkip -Mode adopt -NoGit -SkipEnv | Out-Null
  Assert-True (-not (Test-Path (Join-Path $EnvSkip ".harness/reports"))) "-SkipEnv must not create reports"

  # Env bootstrap: successful setup-env reports ok.
  $EnvOk = Join-Path $Tmp "envok"
  New-Item -ItemType Directory -Force -Path (Join-Path $EnvOk "scripts") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $EnvOk "scripts/setup-env.ps1"), "exit 0")
  & (Join-Path $Root "install.ps1") -Target $EnvOk -Mode adopt -NoGit | Out-Null
  Assert-True ((Get-Content (Join-Path $EnvOk ".harness/reports/env-report.md") -Raw) -match "result: ok") "ok result"

  # Legacy layout is reported but does not fail a complete installation.
  New-Item -ItemType Directory -Force -Path (Join-Path $New ".agents/skills"), (Join-Path $New ".rsi") | Out-Null
  $checkOut = & (Join-Path $Root "install.ps1") -Target $New -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 0) "legacy leftovers must not fail a complete install"
  Assert-True (($checkOut -join "`n") -match "legacy") "legacy report line"

  # Legacy-only project: everything missing -> exit 1 with legacy report.
  $LegacyOnly = Join-Path $Tmp "legacyonly"
  New-Item -ItemType Directory -Force -Path (Join-Path $LegacyOnly ".agents/skills"), (Join-Path $LegacyOnly ".rsi") | Out-Null
  $checkOut = & (Join-Path $Root "install.ps1") -Target $LegacyOnly -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 1) "legacy-only project must fail check"
  Assert-True (($checkOut -join "`n") -match "legacy") "legacy-only report line"

  # Legacy migration: identical files move into .harness/; customized stay + reported.
  $Mig = Join-Path $Tmp "migproj"
  New-Item -ItemType Directory -Force -Path (Join-Path $Mig ".agents/skills/rsi-loop/references"), (Join-Path $Mig ".rsi") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Mig ".agents/skills/rsi-loop/references/stop-conditions.md"), "customized by hand`n")
  [System.IO.File]::WriteAllText((Join-Path $Mig ".rsi/policy.yaml"), "customized policy`n")
  Copy-Item (Join-Path $Root ".harness/skills/rsi-loop/references/gate-policy.md") (Join-Path $Mig ".agents/skills/rsi-loop/references/gate-policy.md")
  $migOut = & (Join-Path $Root "install.ps1") -Target $Mig -Mode adopt -NoGit 6>&1
  Assert-True (-not (Test-Path (Join-Path $Mig ".agents/skills/rsi-loop/references/gate-policy.md"))) "identical legacy file must move"
  Assert-True (Test-Path (Join-Path $Mig ".agents/skills/rsi-loop/references/stop-conditions.md")) "customized legacy file stays"
  Assert-True (Test-Path (Join-Path $Mig ".harness/skills/rsi-loop/references/stop-conditions.md")) "managed copy installed"
  Assert-True (Test-Path (Join-Path $Mig ".harness/.rsi/policy.yaml")) "managed policy installed"
  Assert-True (Test-Path (Join-Path $Mig ".rsi/policy.yaml")) "customized legacy policy stays"
  Assert-True (($migOut -join "`n") -match "left in place") "customized leftovers reported"

  # Legacy hook layout: identical copies at root scripts/ move into
  # .harness/scripts/; customized copies stay in place; the project-owned
  # setup-env.ps1 convention file (G6) is not a managed name and stays untouched.
  $LegacyScripts = Join-Path $Mig "scripts"
  New-Item -ItemType Directory -Force -Path $LegacyScripts | Out-Null
  Copy-Item (Join-Path $Root "scripts/compact-archive.py") (Join-Path $LegacyScripts "compact-archive.py")
  [System.IO.File]::WriteAllText((Join-Path $LegacyScripts "session-recall.py"), ((Get-Content (Join-Path $Root "scripts/session-recall.py") -Raw) + "# local hook tweak`n"))
  [System.IO.File]::WriteAllText((Join-Path $LegacyScripts "setup-env.ps1"), "# project env setup`n")
  $migOut = & (Join-Path $Root "install.ps1") -Target $Mig -Mode adopt -NoGit 6>&1
  Assert-True (-not (Test-Path (Join-Path $LegacyScripts "compact-archive.py"))) "identical legacy hook copy must move"
  Assert-True (Test-Path (Join-Path $Mig ".harness/scripts/compact-archive.py")) "managed hook copy installed"
  Assert-True (Test-Path (Join-Path $LegacyScripts "session-recall.py")) "customized legacy hook copy stays"
  Assert-True (Test-Path (Join-Path $LegacyScripts "setup-env.ps1")) "project-owned setup-env.ps1 untouched"
  Assert-True (($migOut -join "`n") -match "legacy\s+scripts[\\/]session-recall\.py") "customized hook copy reported"
  # -Check reports leftover legacy hook copies without failing (stale state:
  # managed copy missing, root copy present).
  Remove-Item (Join-Path $Mig ".harness/scripts/compact-recall.pi.ts") -Force
  [System.IO.File]::WriteAllText((Join-Path $LegacyScripts "compact-recall.pi.ts"), "x`n")
  $checkOut = & (Join-Path $Root "install.ps1") -Target $Mig -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 0) "legacy hook leftover must not fail a complete check"
  Assert-True (($checkOut -join "`n") -match "legacy\s+scripts/compact-recall\.pi\.ts") "legacy hook copy reported"

  # Layout v1 -> v2 migration: a harness-managed project whose record
  # directories still sit at the root gets them moved under .harness/;
  # destination collisions stay at the root and are reported; the layout
  # marker lands at v2 and an uncustomized v1 policy is upgraded in place.
  $V2 = Join-Path $Tmp "v1proj"
  & (Join-Path $Root "install.ps1") -Target $V2 -Mode auto -NoGit | Out-Null
  Remove-Item (Join-Path $V2 ".harness/layout-version.txt") -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $V2 "docs") | Out-Null
  Move-Item (Join-Path $V2 ".harness/docs/engineering") (Join-Path $V2 "docs/engineering")
  foreach ($d in @("decisions", "issues", "progress", "conversations", "evals")) {
    Move-Item (Join-Path $V2 ".harness/$d") (Join-Path $V2 $d)
  }
  Copy-Item (Join-Path $Root ".harness/templates/project/.rsi/policy-v1.yaml") (Join-Path $V2 ".harness/.rsi/policy.yaml") -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $V2 ".harness/decisions") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $V2 ".harness/decisions/adr.md"), "v2 side content`n")
  [System.IO.File]::WriteAllText((Join-Path $V2 "decisions/adr.md"), "project decision record`n")
  [System.IO.File]::WriteAllText((Join-Path $V2 "docs/product.md"), "my own notes`n")
  $v2Out = & (Join-Path $Root "install.ps1") -Target $V2 -Mode adopt -NoGit 6>&1
  Assert-True ((Get-Content (Join-Path $V2 ".harness/layout-version.txt") -Raw).Trim() -eq "2") "v2 marker after migration"
  Assert-True (Test-Path (Join-Path $V2 ".harness/docs/engineering/index.md")) "rules migrated"
  Assert-True (Test-Path (Join-Path $V2 ".harness/decisions/index.md")) "decisions migrated"
  Assert-True (Test-Path (Join-Path $V2 ".harness/issues/index.md")) "issues migrated"
  Assert-True (Test-Path (Join-Path $V2 ".harness/progress/index.md")) "progress migrated"
  Assert-True (Test-Path (Join-Path $V2 ".harness/conversations/archive")) "conversations migrated"
  Assert-True (Test-Path (Join-Path $V2 ".harness/evals/results")) "evals migrated"
  Assert-True (Test-Path (Join-Path $V2 "docs/product.md")) "project-owned docs content untouched"
  Assert-True (Test-Path (Join-Path $V2 "decisions/adr.md")) "colliding root file survives"
  Assert-True (-not (Test-Path (Join-Path $V2 "docs/engineering"))) "legacy rules dir pruned"
  foreach ($d in @("issues", "progress", "conversations", "evals")) {
    Assert-True (-not (Test-Path (Join-Path $V2 $d))) "legacy $d pruned after migration"
  }
  Assert-True (($v2Out -join "`n") -match "layout v1 -> v2") "migration reported"
  Assert-True (($v2Out -join "`n") -match "conflict decisions/adr\.md") "collision reported"
  Assert-True (($v2Out -join "`n") -match "upgrade\s+\.harness/\.rsi/policy\.yaml") "v1 policy upgraded"
  # Re-running on an already-v2 project is a no-op migration (idempotent).
  $v2Again = & (Join-Path $Root "install.ps1") -Target $V2 -Mode adopt -NoGit 6>&1
  Assert-True (($v2Again -join "`n") -match "layout   v2") "idempotent on v2"
  # -Check reports a v1 project without failing a complete install.
  Remove-Item (Join-Path $V2 ".harness/layout-version.txt") -Force
  [System.IO.File]::WriteAllText((Join-Path $V2 "decisions/stale.md"), "v1 leftover`n")
  $v1Check = & (Join-Path $Root "install.ps1") -Target $V2 -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 0) "layout v1 leftover must not fail a complete check"
  Assert-True (($v1Check -join "`n") -match "legacy\s+layout v1") "layout v1 reported by -Check"

  # A project WITHOUT .harness/ is fresh (version 0) even when it carries its
  # own root-level decisions/ and progress/: nothing moves, and the v2 record
  # directories are created alongside the project's own content.
  $Plain = Join-Path $Tmp "plainproj"
  New-Item -ItemType Directory -Force -Path (Join-Path $Plain "decisions"), (Join-Path $Plain "progress") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Plain "decisions/our-adr.md"), "pre-existing project decision`n")
  [System.IO.File]::WriteAllText((Join-Path $Plain "progress/notes.md"), "project progress note`n")
  $plainOut = & (Join-Path $Root "install.ps1") -Target $Plain -Mode adopt -NoGit 6>&1
  Assert-True (($plainOut -join "`n") -match "layout\s+v2 \(fresh install\)") "fresh project detected as v2"
  Assert-True (Test-Path (Join-Path $Plain "decisions/our-adr.md")) "project-owned decisions untouched"
  Assert-True (Test-Path (Join-Path $Plain "progress/notes.md")) "project-owned progress untouched"
  Assert-True (Test-Path (Join-Path $Plain ".harness/decisions/index.md")) "v2 record dir created"
  Assert-True (Test-Path (Join-Path $Plain ".harness/evals/results")) "v2 verdict dir created"
  Assert-True (-not (Test-Path (Join-Path $Plain ".harness/decisions/our-adr.md"))) "project content not pulled into .harness"

  # Anti-nesting guard: bare relative -Target from an empty cwd is refused.
  $Nest = Join-Path $Tmp "nestcwd"
  New-Item -ItemType Directory -Force -Path $Nest | Out-Null
  Push-Location $Nest
  & (Join-Path $Root "install.ps1") -Target my-project -Mode auto -NoGit 2>&1 | Out-Null
  Pop-Location
  Assert-True ($LASTEXITCODE -eq 2) "anti-nesting guard must exit 2"
  Assert-True (-not (Test-Path (Join-Path $Nest "my-project"))) "guard must not create the nested dir"

  # Escape hatch: explicit .\name still nests on purpose.
  Push-Location $Nest
  & (Join-Path $Root "install.ps1") -Target .\my-project -Mode auto -NoGit | Out-Null
  Pop-Location
  Assert-True ($LASTEXITCODE -eq 0) "explicit .\name nested flow works"
  Assert-True (Test-Path (Join-Path $Nest "my-project/AGENTS.md")) "nested project installed"

  # Documented flow: non-empty cwd + bare name still works.
  $Docu = Join-Path $Tmp "docucwd"
  New-Item -ItemType Directory -Force -Path $Docu | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Docu "seed.txt"), "seed")
  Push-Location $Docu
  & (Join-Path $Root "install.ps1") -Target my-project -Mode auto -NoGit | Out-Null
  Pop-Location
  Assert-True ($LASTEXITCODE -eq 0) "bare -Target from non-empty cwd works"
  Assert-True (Test-Path (Join-Path $Docu "my-project/AGENTS.md")) "subproject installed"

  # git init: fresh target gets a repository; re-run keeps it; .git FILE counts.
  $GitProj = Join-Path $Tmp "gitproj"
  New-Item -ItemType Directory -Force -Path $GitProj | Out-Null
  & (Join-Path $Root "install.ps1") -Target $GitProj -Mode auto | Out-Null
  Assert-True (Test-Path (Join-Path $GitProj ".git")) "git init ran on fresh target"
  $gitAgain = & (Join-Path $Root "install.ps1") -Target $GitProj -Mode auto 6>&1
  Assert-True (($gitAgain -join "`n") -match "keep\s+\.git") "second run keeps .git"
  $GitFile = Join-Path $Tmp "gitfile"
  New-Item -ItemType Directory -Force -Path $GitFile | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $GitFile ".git"), "gitdir: /elsewhere")
  $gitFileOut = & (Join-Path $Root "install.ps1") -Target $GitFile -Mode auto 6>&1
  Assert-True (($gitFileOut -join "`n") -match "keep\s+\.git") ".git file counts as initialized"
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $GitFile ".git") -PathType Container)) ".git file left untouched"

  Write-Host "install smoke test: PASS"
}
finally {
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
