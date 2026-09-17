[CmdletBinding()]
param(
    [ValidateSet('Setup', 'Check', 'Collect')]
    [string]$Mode = 'Setup',
    [string]$Name = 'Corridor',
    [string]$Distribution = 'Ubuntu-22.04'
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL is not installed. This collector needs Ubuntu 22.04 in WSL2. See README.md.'
}
$distributions = (& wsl.exe --list --quiet 2>$null) -replace "`0", ''
if ($LASTEXITCODE -ne 0 -or -not ($distributions | Where-Object { $_.Trim() -eq $Distribution })) {
    throw "Ubuntu distribution '$Distribution' is not installed or ready. Run 'wsl --list --verbose' to check. See README.md for installation."
}
switch ($Mode) {
    'Setup' {
        # Repair existing Windows checkouts made before the LF attribute existed.
        & wsl.exe -d $Distribution --cd $PSScriptRoot -- bash -c 'sed -i ''s/\r$//'' setup.sh; bash ./setup.sh'
    }
    'Check' {
        & wsl.exe -d $Distribution --cd $PSScriptRoot -- python3 collect.py --check
    }
    'Collect' {
        & wsl.exe -d $Distribution --cd $PSScriptRoot -- python3 collect.py --name $Name --execute
    }
}
exit $LASTEXITCODE
