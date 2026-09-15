# Wrapper: locate a Python interpreter and run install-agent-hooks.py.
$ErrorActionPreference = 'SilentlyContinue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($py in @('python', 'python3', 'py')) {
    $cmd = Get-Command $py -ErrorAction SilentlyContinue
    if ($cmd) {
        & $cmd.Source "$dir\install-agent-hooks.py" @args
        exit $LASTEXITCODE
    }
}
Write-Host '[install-agent-hooks] no python interpreter found'
exit 1
