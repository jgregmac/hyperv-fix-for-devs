<#
.SYNOPSIS
    Enables the Hyper-V Fix, invokes a WSL2 command, then disables the adapter.
#>
[CmdletBinding()]
param (
    # Name of the dummy adapter used for fixing the Hyper-V network.
    [Parameter(Mandatory=$true)]
    [string]$AdapterName,
    
    # IP address for the adapter.
    [Parameter(Mandatory=$true)]
    [IPAddress]$LoopbackIP,

    # Netmask length for the adapter.
    [Parameter(Mandatory=$true)]
    [int]$LoopbackNetLength
)

$logRoot = Split-Path $script:MyInvocation.MyCommand.Path -Parent
$logfilepath = Join-Path -Path $logRoot -ChildPath HyperVNetFix.log

function WriteToLogFile ($message) {
    Out-File -FilePath $logfilepath -InputObject $message -Append -Encoding utf8
}
if (Test-Path $logfilepath) {
    Remove-Item $logfilepath
}

Get-NetAdapter -Name $AdapterName | Enable-NetAdapter
WriteToLogFile "Hyper-V Fix Adapter Enabled."
if ( -not (Get-NetIPAddress -IPAddress $LoopbackIP.ToString() -ea SilentlyContinue) ) {
    WriteToLogFile "Hyper-V Fix adapter has not IP address. Let's add it."
    New-NetIPAddress -IPAddress $LoopbackIP.ToString() -PrefixLength $LoopbackNetLength `
        -InterfaceAlias "$AdapterName" -ea Stop 
}

# Assuming the above steps completed successfully, let's try to start up WSL
if ( Get-NetIPAddress -IPAddress $LoopbackIP.ToString() -ErrorAction SilentlyContinue ) {
    # Run some useless command in the WSL VM to force the VM and default distro to start:
    wsl.exe --exec pwd
    WriteToLogFile "WSL Started."
} else {
    WriteToLogFile "The required blocking IP address is not present.  Exiting."
    exit 100
}

Get-NetAdapter -Name $AdapterName | Disable-NetAdapter -Confirm:$false
WriteToLogFile "Hyper-V Fix Adapter Disabled."

WriteToLogFile "IP Config after Applying Fix:"
ipconfig | Out-File -Append -FilePath $logfilepath -Encoding utf8
