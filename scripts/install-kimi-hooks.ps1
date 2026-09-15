# Kimi Code compat shim - the generic installer handles kimi hooks:
#   scripts/install-agent-hooks.ps1 kimi -Target <project>
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$dir\install-agent-hooks.ps1" kimi @args
exit $LASTEXITCODE
