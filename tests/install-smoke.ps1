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

  # Empty project should receive canonical init layout under .harness/.
  Assert-True (Test-Path (Join-Path $New "AGENTS.md")) "new/AGENTS.md"
  Assert-True (Test-Path (Join-Path $New "CLAUDE.md")) "new/CLAUDE.md"
  Assert-True ((Get-Content (Join-Path $New "AGENTS.md") -Raw) -match "ris-coding-harness:begin") "AGENTS managed markers"
  Assert-True ((Get-Content (Join-Path $New "CLAUDE.md") -Raw) -match "ris-coding-harness:begin") "CLAUDE managed markers"
  Assert-True (Test-Path (Join-Path $New "src/index.md")) "new/src/index.md"
  Assert-True (Test-Path (Join-Path $New "docs/engineering/index.md")) "new rules index"
  Assert-True (Test-Path (Join-Path $New "docs/engineering/platform/index.md")) "new platform index"
  Assert-True (Test-Path (Join-Path $New ".harness/skills/pm-workers-engineering/SKILL.md")) "new skill"
  Assert-True (Test-Path (Join-Path $New ".harness/skills/rsi-loop/SKILL.md")) "new rsi-loop"
  Assert-True (Test-Path (Join-Path $New ".harness/skills/rsi-loop/references/preflight.md")) "new rsi-loop preflight"
  Assert-True (Test-Path (Join-Path $New ".harness/.rsi/policy.yaml")) "new policy"
  Assert-True (Test-Path (Join-Path $New ".harness/manifest.json")) "new manifest"
  Assert-True ((Get-Content (Join-Path $New ".harness/manifest.json") -Raw) -match '"sha256"') "manifest hashes"
  Assert-True (Test-Path (Join-Path $New "evals/results")) "new evals/results"

  # Existing project should be adopted without canonical source/test directories.
  Assert-True (Test-Path (Join-Path $Existing "AGENTS.md")) "existing/AGENTS.md"
  Assert-True (Test-Path (Join-Path $Existing "docs/engineering/index.md")) "existing rules index"
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
  [System.IO.File]::WriteAllText((Join-Path $Existing "docs/engineering/coding.md"), "# local customization`n")
  & (Join-Path $Root "install.ps1") -Target $Existing -Mode adopt -NoGit | Out-Null
  $coding = Get-Content (Join-Path $Existing "docs/engineering/coding.md") -Raw
  Assert-True ($coding -match "^# local customization") "local customization preserved"

  # -Agent claude,opencode,codex installs the skill to .harness plus all three agent dirs.
  $Multi = Join-Path $Tmp "multi"
  New-Item -ItemType Directory -Force -Path $Multi | Out-Null
  & (Join-Path $Root "install.ps1") -Target $Multi -Mode adopt -NoGit -Agent claude,opencode,codex | Out-Null
  Assert-True (Test-Path (Join-Path $Multi ".harness/skills/pm-workers-engineering/SKILL.md")) "multi .harness skill"
  Assert-True (Test-Path (Join-Path $Multi ".claude/skills/pm-workers-engineering/SKILL.md")) "multi .claude skill"
  Assert-True (Test-Path (Join-Path $Multi ".opencode/skills/pm-workers-engineering/SKILL.md")) "multi .opencode skill"
  Assert-True (Test-Path (Join-Path $Multi ".codex/skills/pm-workers-engineering/SKILL.md")) "multi .codex skill"

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

  # -Check covers skills, policy, and the AGENTS.md managed section.
  $checkOut = & (Join-Path $Root "install.ps1") -Target $New -Check 6>&1
  Assert-True ($LASTEXITCODE -eq 0) "-Check must pass after install"
  Assert-True (($checkOut -join "`n") -match "\.harness/.rsi/policy\.yaml") "policy check line"
  Assert-True (($checkOut -join "`n") -match "AGENTS\.md managed section") "managed section check line"

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
  $coding = Get-Content (Join-Path $Existing "docs/engineering/coding.md") -Raw
  Assert-True ($coding -match "^# local customization") "local customization preserved"

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
