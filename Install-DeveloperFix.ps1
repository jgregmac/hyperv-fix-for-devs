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
    [Parameter()]
    [string]
    $AdapterName = "Hyper-V Fix",

    <#
      An IP address in the network range used by your organization. 
      Common values would be:
      - 172.16.0.1 for class B private networks
      - 192.168.0.1 for class C private networks
    #>
    [Parameter()]
    [IPAddress]
    $LoopbackIP = "172.16.0.1",

    <# 
      The netmask length that covers the entirety of the private network range used 
      by your organization.
      Common values would be:
      - 12 for class B (172.16) private networks
      - 16 for class C (192.168) private networks
    #>
    [Parameter()]
    [ValidateRange(1,32)]
    [int]
    $LoopbackNetLength = 12,

    <# Target directory for the startup/shutdown scripts.  Default is a "Hyper-V-Fix" 
    directory under your user profile. #>
    [Parameter()]
    [string]
    $ScriptDestination = (Join-Path -Path $env:USERPROFILE -ChildPath "Hyper-V-Fix")
)

# The installer will create the tasks to run under the account of the user running this
# installer script.  You could force installation for a specific user by changing these
# variables, but the target user /has to/ have a working WSL instance to launch at login.
# This scenario has not been tested, so it will remain a "constant" in the script for now.
# Both the user name (in DomainName\UserName) and SID are required:
$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$UserSID = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

#region Copy scripts to current user profile
    if (-not (Test-Path $ScriptDestination )) {
        New-Item -ItemType Directory -Path $ScriptDestination -ea Stop
    }
    $CurrentPath = Split-Path  $script:MyInvocation.MyCommand.Path -Parent
    #Write-Host "CurrentPath is: $CurrentPath"
    $ScriptSource = Join-Path -Path $CurrentPath -ChildPath scripts
    #Write-Host "ScriptSource is: $ScriptSource"
    Copy-Item -Path (Join-Path -Path $ScriptSource -ChildPath "*.ps1").ToString() `
        -Destination $ScriptDestination -Force -Confirm:$false -ea Stop
#endregion

#region Create Scheduled Tasks
    $TaskSource = Join-Path -Path $CurrentPath -ChildPath tasks
    #Write-Host "TaskSource is: $TaskSource"
    $TaskStage = Join-Path -Path $env:TEMP -ChildPath tasks
    #Write-Host "TaskStage is: $TaskStage"
    if (-not (Test-Path $TaskStage)) {
        New-Item -ItemType Directory -Path $TaskStage -ea Stop
    }
    # Read the content of our scheduled task templates from the source,
    # Update the templates with local user data, and write to the $env:temp directory.
    Get-ChildItem -Path $TaskSource | ForEach-Object {
        #Write-Host ("Working on source file: " + $_.FullName);
        $Leaf = $_.Name;
        Get-Content $_.FullName | 
            ForEach-Object { $_ -replace "USER_ID", $UserName } |
            ForEach-Object { $_ -replace "USER_SID", $UserSID } |
            ForEach-Object { $_ -replace "STARTUP_SCRIPT_PATH", $ScriptDestination } |
            ForEach-Object { $_ -replace "ADAPTER_NAME", $AdapterName } |
            Set-Content -Path (Join-Path -Path $TaskStage -ChildPath $Leaf) -Force -Confirm:$false -ea Stop;
    }
    # Register the login actions task
    $SourceFile = Join-Path -Path $TaskStage -ChildPath login-task.xml -Resolve
    Register-ScheduledTask -Xml (Get-Content $SourceFile | Out-String) `
        -TaskName "Hyper-V and WSL Net Fix - Startup Tasks" -Force -ea Stop
    # Register the shutdown actions task
    $SourceFile = Join-Path -Path $TaskStage -ChildPath shutdown-task.xml -Resolve
    Register-ScheduledTask -Xml (Get-Content $SourceFile | Out-String) `
        -TaskName "Hyper-V and WSL Net Fix - Shutdown Task" -Force -ea Stop
#endregion

#region Install Loopback Adapter
    # Install the LoopbackAdapter module from the PSGallery, if not present:
    if ( -not (Get-Module -ListAvailable -Name LoopbackAdapter -ea SilentlyContinue )) {
        Install-Module LoopbackAdapter -Force -Confirm:$false -ea Stop
    }
    Import-Module LoopbackAdapter
    # Create the Loopback Adapter:
    if (Get-NetAdapter -Name $AdapterName -ea SilentlyContinue) {
        $index = Get-NetAdapter -Name $AdapterName | Select-Object -ExpandProperty ifIndex
        Enable-NetAdapter -Name $AdapterName -ea SilentlyContinue
        Remove-NetIPAddress -InterfaceIndex $index -Confirm:$false -ea Stop
        Remove-LoopbackAdapter -Name $AdapterName -Force -ea Stop
    }
    New-LoopbackAdapter -Name $AdapterName | Out-Null
    # Assign an IP to the adapter and disable it:
    if ( -not (Get-NetIPAddress -IPAddress $LoopbackIP.ToString() -ea SilentlyContinue) ) {
        New-NetIPAddress -IPAddress $LoopbackIP.ToString() -PrefixLength $LoopbackNetLength `
            -InterfaceAlias "$AdapterName" -ea Stop | Out-Null
    }
    Disable-NetAdapter -Name $AdapterName -Confirm:$false
#endregion