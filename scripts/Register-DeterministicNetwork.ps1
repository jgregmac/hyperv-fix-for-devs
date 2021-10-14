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
    # Type of virtual network that will be configured.  Supported options are "WSL" or "Hyper-V".
    [Parameter()]
    [ValidateSet("WSL", "Hyper-V")]
    [string]$NetworkType = "WSL",

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

switch ($NetworkType) {
    "WSL" {
        [string] $HnsName      = "WSL"
        [guid]   $HnsNetworkId = "B95D0C5E-57D4-412B-B571-18A81A16E005"
        [guid]   $ParentID     = "21894F4E-9F9C-41B5-B8EF-87948943C15E"
        [guid]   $ChildID      = "28D2ABF3-7D0A-45E8-9954-62E2D24269A6"
        [string] $Flags        = 9
        [string] $MacPoolStart = "00-15-5D-9B-F0-00"
        [string] $MacPoolEnd   = "00-15-5D-9B-FF-FF"
        [string] $MaxEndpoints = 1
        $ExtraEntries = @"

    "IsolateSwitch": true,
"@
        # Auto-created WSL Switch also has:
        # GatewayMac             : 00-15-5D-9B-F6-0B
        # LayeredOn              : IGNORE - it changes on every reboot!
        # NatName                : IGNORE - it changes on every reboot!
        # Extensions             : {@{Id=E7C3B2F0-F3C5-48DF-AF2B-10FED6D72E7A; IsEnabled=False; Name=Microsoft Windows Filtering
        #     Platform}, @{Id=EA509342-793C-4020-A3E7-9C0928454D89; IsEnabled=False; Name=Microsoft
        #     Defender Application Guard Filter Driver}, @{Id=E9B59CFA-2BE1-4B21-828F-B6FBDBDDC017;
        #     IsEnabled=False; Name=Microsoft Azure VFP Switch Extension},
        #     @{Id=430BDADD-BAB0-41AB-A369-94B67FA5BE0A; IsEnabled=True; Name=Microsoft NDIS Capture}}
    }
    "Hyper-V" {
        [string] $HnsName      = "Default Switch"
        [guid]   $HnsNetworkId = "C08CB7B8-9B3C-408E-8E30-5E16A3AEB444"
        [guid]   $ParentID     = "B81F1F65-3F5A-4789-962F-009DBC86F1C8"
        [guid]   $ChildID      = "2723DF08-8F13-4408-B2D9-F8AF6FE00592"
        [string] $Flags        = 11
        [string] $MacPoolStart = "00-15-5D-17-30-00"
        [string] $MacPoolEnd   = "00-15-5D-17-3F-FF"
        [string] $MaxEndpoints = 0
        $ExtraEntries = @"

    "SwitchName": "$HnsName",
    "SwitchGuid": "$HnsNetworkId",
"@
        # Auto-created Default Switch also has:
        # NatName: Ignore this, it changes on each reboot.
        # GatewayMac             : 00-15-5D-01-3E-00
        # Extensions             : {@{Id=E7C3B2F0-F3C5-48DF-AF2B-10FED6D72E7A; IsEnabled=False; Name=Microsoft Windows Filtering
        #     Platform}, @{Id=EA509342-793C-4020-A3E7-9C0928454D89; IsEnabled=True; Name=Microsoft Defender
        #     Application Guard Filter Driver}, @{Id=E9B59CFA-2BE1-4B21-828F-B6FBDBDDC017; IsEnabled=False;
        #     Name=Microsoft Azure VFP Switch Extension}, @{Id=430BDADD-BAB0-41AB-A369-94B67FA5BE0A;
    }
    Default { exit 100 }
}

# Let's try using fixed GUIDs instead...
# $Guid1 = New-Guid
# $Guid2 = New-Guid
# $HnsNetworkConfig is the configuration block for the new HNS network for WSL.
# Note:  For NAT, use Flags = 0 and Type = NAT.

$HnsNetworkConfig = @"
{
    "Name" : "$HnsName",
    "Flags": $Flags,
    "Type": "ICS",
    "IPv6": false,
    "MaxConcurrentEndpoints": $MaxEndpoints,
    "Subnets" : [
        {
            "ID" : "$ParentID",
            "ObjectType": 5,
            "AddressPrefix" : "$NetworkAddress",
            "GatewayAddress" : "$GatewayAddress",
            "IpSubnets" : [
                {
                    "ID" : "$ChildID",
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
    ],$ExtraEntries
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

