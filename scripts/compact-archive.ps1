# Kimi Code PostCompact hook wrapper: locate a Python interpreter and run
# compact-archive.py. Fail-open: exits 0 when no interpreter is found so the
# hook never blocks compaction.
$ErrorActionPreference = 'SilentlyContinue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($py in @('python', 'python3', 'py')) {
    $cmd = Get-Command $py -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source "$dir\compact-archive.py" @args
        exit $LASTEXITCODE
    }
}
Write-Host '[compact-archive] no python interpreter found; skipping'
exit 0
