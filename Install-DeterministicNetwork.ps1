<#
.SYNOPSIS
    Installation Script for the Hyper-V / WSL2 Network Fix for Developers

.DESCRIPTION
    Linux developers who choose (or are forced) to use Windows will benefit greatly
    from the use the the Windows Subsystem for Linux, and the Hyper-V virtualization
    engine.  Unfortunately, these tools often run into problems with corporate use of 
    private network ranges, especially when the developer using the system roams
    between remote and on-site work, or needs a VPN connection.

    The problem is that Hyper-V selects private network ranges for internal use based
    on the networks that it can "see" when the system starts up.  If the private networks
    in use change after startup, there may be a network collision.  Networking inside
    the Hyper-V and WSL VMs then fail, and sometimes general networking on the host
    Windows system deteriorates as well.  Microsoft does not appear to be interested in
    fixing this common problem.

    This tool will install a Loopback network adapter and startup and shutdown scripts
    that are designed to "trick" the Hyper-V (and WSL) network collision avoidance 
    algorithm into using a network range of our choosing that we know will not collide
    with our corporate internal private networks.
#>
[CmdletBinding()]
param (
    # Name of the dummy adapter that will be created.
    # Only testing this for WSL at present... will need to re-install Hyper-V to validate:
    [Parameter()]
    [ValidateSet("WSL", "Hyper-V")]
    [string]
    $NetworkType = "WSL",

    <#
      The IP address to be used on the interface created for WSL/Hyper-V.  Thi will serve
      as the gateway address for the new virtual network. Examples:
      - 192.168.100.1 (Default) - A class C private network that is unlikely to collide with most home networks.
      - 172.16.100.1 - A class B private network, which might collide with a corporate network.
      - 10.100.100.1 - A class A private network, less likely to collide with a corporate network, but it could!
    #>
    [Parameter()]
    [IPaddress]
    $GatewayAddress = "192.168.100.1",

    <#
      The network address, in CIDR notation, to be assigned to the new virtual network.
      See: <https://docs.netgate.com/pfsense/en/latest/network/cidr.html>
      The default is 192.168.100.0/24.
    #>
    [Parameter()]
    [string]
    $NetworkAddress = "192.168.100.0/24",

    <# Target directory for the startup/shutdown scripts.  Default is a "$NetworkType-Network-Fix" 
    directory under your user profile. #>
    [Parameter()]
    [string]
    $ScriptDestination = (Join-Path -Path $env:USERPROFILE -ChildPath "$NetworkType-Network-Fix")
)

# Establish current path and logging:
$CurrentPath = Split-Path  $script:MyInvocation.MyCommand.Path -Parent
Import-Module (Join-Path -Path $CurrentPath -ChildPath "\scripts\OutConsoleAndLog.psm1") -ea Stop
$global:GlobalLog = (Join-Path -Path $CurrentPath -ChildPath "Install-Deterministric-$NetworkType-Network.log")
if (Test-Path $GlobalLog) { Remove-Item -Path $GlobalLog -Force -Confirm:$false }

Out-ConsoleAndLog "Starting installation of the $NetworkType Network Fix." 
Out-ConsoleAndLog "These messages will be logged to: $GlobalLog" 

# The installer will create the tasks to run under the account of the user running this
# installer script.  You could force installation for a specific user by changing these
# variables, but the target user /has to/ have a working WSL instance to launch at login.
# This scenario has not been tested, so it will remain a "constant" in the script for now.
# Both the user name (in DomainName\UserName) and SID are required:
$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$UserSID = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
Out-ConsoleAndLog "Generated Tasks will be run as $UserName with SID: $UserSID" 

#region Copy scripts to current user profile
    Out-ConsoleAndLog "Scripts will be copied to directory: $ScriptDestination" 
    if (-not (Test-Path $ScriptDestination )) {
        Out-ConsoleAndLog "Creating script directory..." 
        New-Item -ItemType Directory -Path $ScriptDestination -ea Stop -Force | Out-Null
    }
    #Write-Host "CurrentPath is: $CurrentPath"
    $ScriptSource = Join-Path -Path $CurrentPath -ChildPath scripts
    #Write-Host "ScriptSource is: $ScriptSource"
    Out-ConsoleAndLog "Copying scripts into place..."
    Copy-Item -Path (Join-Path -Path $ScriptSource -ChildPath "*.ps*1").ToString() `
        -Destination $ScriptDestination -Force -Confirm:$false -ea Stop
#endregion

#region Create Scheduled Tasks
    $TaskSource = Join-Path -Path $CurrentPath -ChildPath tasks
    $TaskStage = Join-Path -Path $env:TEMP -ChildPath "$NetworkType-tasks"
    Out-ConsoleAndLog "Staging task definitions to: $TaskStage"
    if (-not (Test-Path $TaskStage)) {
        Out-ConsoleAndLog "Creating staging directory: '$TaskStage'..."
        New-Item -ItemType Directory -Path $TaskStage -Force -ea Stop | Out-Null
    }
    # Read the content of our scheduled task templates from the source,
    # Update the templates with local user data, and write to the $env:temp directory.
    Out-ConsoleAndLog "Updating the staged task definitions:"
    Get-ChildItem -Path $TaskSource | ForEach-Object {
        #Write-Host ("Working on source file: " + $_.FullName);
        $Leaf = $_.Name;
        Get-Content $_.FullName | 
            ForEach-Object { $_ -replace "USER_ID", $UserName } |
            ForEach-Object { $_ -replace "USER_SID", $UserSID } |
            ForEach-Object { $_ -replace "STARTUP_SCRIPT_PATH", $ScriptDestination } |
            ForEach-Object { $_ -replace "NETWORK_TYPE", $NetworkType } |
            ForEach-Object { $_ -replace "IP_ADDRESS", $GatewayAddress } |
            ForEach-Object { $_ -replace "NETWORK_ADDRESS", $NetworkAddress } |
            Set-Content -Path (Join-Path -Path $TaskStage -ChildPath $Leaf) -Force -Confirm:$false -ea Stop;
    }
    # Register the login actions task
    Out-ConsoleAndLog "Registering the startup/login task..."
    $SourceFile = Join-Path -Path $TaskStage -ChildPath login-task.xml -Resolve
    Register-ScheduledTask -Xml (Get-Content $SourceFile | Out-String) `
        -TaskName "$NetworkType Fix Task - On Startup" -Force -ea Stop | Out-Null
    # Remove-Item -Recurse -Path $TaskStage -Force
#endregion

Out-ConsoleAndLog "All done. $NetworkType Network Fix Startup Script has been installed."