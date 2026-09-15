# Kimi Code UserPromptSubmit hook wrapper: locate a Python interpreter and run
# session-recall.py. Fail-open: exits 0 when no interpreter is found.
$ErrorActionPreference = 'SilentlyContinue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($py in @('python', 'python3', 'py')) {
    $cmd = Get-Command $py -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source "$dir\session-recall.py" @args
        exit $LASTEXITCODE
    }
}
Write-Host '[session-recall] no python interpreter found; skipping'
exit 0
