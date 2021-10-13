<#
.SYNOPSIS
    Creates or Re-creates the Hyper-V or WSL private network with the specified
    (deterministic) network range.
.DESCRIPTION
    Normally, Hyper-V/WSL uses a collision-avoidance algorithm when assigning private
    network ranges to the virtual network that it creates for Hyper-V based networks.
    This is fine for many use cases, but remote and roaming users on corporate networks
    may find this behavior unacceptable as the network that Windows thought was
    non-conflicting at system startup may become conflicting when you later start a VPN
    connection to your business network.

    This script allows you to specify a deterministic network range and gatweway to use
    for WSL or Hyper-V.  The network will be re-created on each startup to ensure
    continuity.
#>
[CmdletBinding()]
param (
    # Name of the dummy adapter used for fixing the Hyper-V network.
    [Parameter()]
    [ValidateSet("WSL", "Hyper-V")]
    [string]$NetworkName = "WSL",

    # IP address for the adapter (This address will service as the gateway address for the network.)
    [Parameter(Mandatory=$true)]
    [IPAddress]$GatewayAddress,

    # Address and mask bits for the network, in CIDR notation.
    [Parameter(Mandatory=$true)]
    [string]$NetworkAddress
)

# Establish current path and logging:
$CurrentPath = Split-Path  $script:MyInvocation.MyCommand.Path -Parent
$global:GlobalLog = (Join-Path -Path $CurrentPath -ChildPath "Register-$NetworkName-Network.log")
if (Test-Path $GlobalLog) { Remove-Item -Path $GlobalLog -Force -Confirm:$false }

# Load our custom logging module:
Import-Module (Join-Path -Path $CurrentPath -ChildPath "OutConsoleAndLog.psm1")

# Load the HCN script with custom HNSNetwork functions.  There is an "HCN" module available
# In the PowerShell gallery, upon which these functions are based, but it does not allow
# us to set the NetworkID of the network, which is necessary for the fixed WSL and Hyper-V nets.
# See: <https://github.com/skorhone/wsl2-custom-network/blob/main/hcn/Hcn.psm1>
. (Join-Path -Path $CurrentPath -ChildPath "HCN.ps1") -ea Stop

switch ($NetworkName) {
    "WSL" {
        [string]$HnsName = "WSL"
        [guid]$HnsNetworkId = "B95D0C5E-57D4-412B-B571-18A81A16E005"
        [string]$MacPoolStart="00-15-5D-52-C0-00"
        [string]$MacPoolEnd="00-15-5D-52-CF-FF"
    }
    "Hyper-V" {
        [string]$HnsName = "Default Switch"
        [guid]$HnsNetworkId = "C08CB7B8-9B3C-408E-8E30-5E16A3AEB444"
        [string]$MacPoolStart="00-15-5D-D2-B0-00"
        [string]$MacPoolEnd="00-15-5D-D2-BF-FF"
    }
    Default { exit 100 }
}

# We need some random guids for objects embedded within the created netwrok...
$Guid1 = New-Guid
$Guid2 = New-Guid
# $HnsNetworkConfig is the configuration block for the new HNS network for WSL.
# Note:  For NAT, use Flags = 0 and Type = NAT.
$HnsNetworkConfig = @"
{
    "Name" : "$HnsName",
    "Flags": 9,
    "Type": "ICS",
    "IPv6": false,
    "IsolateSwitch": true,
    "MaxConcurrentEndpoints": 1,
    "Subnets" : [
        {
            "ID" : "$Guid1",
            "ObjectType": 5,
            "AddressPrefix" : "$NetworkAddress",
            "GatewayAddress" : "$GatewayAddress",
            "IpSubnets" : [
                {
                    "ID" : "$Guid2",
                    "Flags": 3,
                    "IpAddressPrefix": "$NetworkAddress",
                    "ObjectType": 6
                }
            ]
        }
    ],
    "MacPools":  [
        {
            "EndMacAddress":  "$MacPoolEnd",
            "StartMacAddress":  "$MacPoolStart"
        }
    ],
    "DNSServerList" : "$GatewayAddress"
}
"@

# Remove any existing HNS network:
$oldNet = Get-HnsNetworkEx -Id $HnsNetworkId -ea SilentlyContinue
if ($oldNet) {Remove-HnsNetworkEx $oldNet}
Out-ConsoleAndLog "Network Configuration to Create:" 
Out-ConsoleAndLog $HnsNetworkConfig

# Create a new network:
New-HnsNetworkEx -Id $HnsNetworkId -JsonString $HnsNetworkConfig | Out-Null

# Check on the resulting adapter:
$newAdapter = Get-NetAdapter -Name "vEthernet ($HnsName)"

if ($newAdapter) {
    # Out-ConsoleAndLog "Pausing while the adapter initializes..."
    # start-sleep -Seconds 5
    if ($newAdapter.Status -eq "Up") {
        Out-ConsoleAndLog "$NetworkName adapter enabled."
        $AddressArray = @()
        $AddressArray += Get-NetIPAddress -InterfaceIndex $newAdapter.InterfaceIndex
        if ($GatewayAddress -in ($AddressArray).IPAddress) {
            Out-ConsoleAndLog "$NetworkName adapter has the intended IP Address."
        } else {
            Out-ConsoleAndLog "$NetworkName adapter is not configured correctly."
            exit 101
        }
    } else {
        Out-ConsoleAndLog "$NetworkName adapter is not enabled.  This may not be important yet."
    }
} else {
    Out-ConsoleAndLog "WSL network adapter is not present.  Somthing went wrong."
    exit 100
}

Out-ConsoleAndLog "Current IPs of adapter: "
foreach ($ip in $AddressArray) {
    Out-ConsoleAndLog $ip.ToString()
}

