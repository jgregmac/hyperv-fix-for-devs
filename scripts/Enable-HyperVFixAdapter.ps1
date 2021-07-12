<#
.SYNOPSIS
    Enables the Hyper-V Fix adapter 
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
$logfilepath = Join-Path -Path $logRoot -ChildPath EnableHyperVAdapter.log

function WriteToLogFile ($message) {
    Out-File -FilePath $logfilepath -InputObject $message -Append -Encoding utf8
}
if (Test-Path $logfilepath) {
    Remove-Item $logfilepath
}

$hvAdapter = Get-NetAdapter -Name $AdapterName
if ($hvAdapter) {
    if ($hvAdapter.Status -eq "Disabled") {
        Enable-NetAdapter -Name $hvAdapter.Name
        WriteToLogFile "Hyper-V Fix adapter enabled."
    } else {
        WriteToLogFile "Hyper-V Fix adapter already enabled."
    }
} else {
    WriteToLogFile "Hyper-V Fix adapter does not exist."
    exit 100
}

WriteToLogFile "Current IP of adapter: "
$CurrentIP = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4
[string]$ipString = ($CurrentIP.IPAddress + "/" + $CurrentIP.PrefixLength.ToString())
WriteToLogFile $ipString

if ( $CurrentIP.IPAddress -ne $LoopbackIP ) {
    WriteToLogFile "Hyper-V Fix adapter has the wrong address.  Let' fix that..."
    Remove-NetIPAddress -IPAddress $CurrentIP.IPAddress -Confirm:$false
    New-NetIPAddress -IPAddress $LoopbackIP.ToString() -PrefixLength $LoopbackNetLength `
        -InterfaceAlias "$AdapterName" -ea Stop 
    WriteToLogFile "IPv4 address of the adapter after fix:"
    $CurrentIP = Get-NetIPAddress -InterfaceAlias $AdapterName -AddressFamily IPv4
    [string]$ipString = ($CurrentIP.IPAddress + "/" + $CurrentIP.PrefixLength.ToString())
    WriteToLogFile $ipString
}
