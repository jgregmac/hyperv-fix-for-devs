# Hyper-V and WSL2 Network Fix for Linux Developers

A work-around for the annoying networking problems that plague WSL2 / Hyper-V users who
roam or use VPN connections to get work done.

## Prerequisites

- You must have "Administrator" privileges on your system to run this script
- Script tested onyl on Windows 10 21H1 with PowerShell 5 and 7.1.
- The script uses the PowerShell Gallery community module "LoopbackAdapter". This Module is not maintained by Microsoft, and uses external binaries to manage virtual hardware on your system.

## Usage

1. Start by cloning this repository, or downloading its contents to your system.  You need the _entire_
repository contents, not just the Install-DeveloperFix.ps1 script.  
2. Open a PowerShell prompt in the directory with the script and run the following commands:

    ```powershell
    # This script is not signed, so you need to set ExecutionPolicy to "RemoteSigned" or 
    # "Unrestricted" to run it, if you have not already done so.
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted

    # (If you download the code bundle from GitHub instead of cloning the repo, you may
    # need to "unblock" the scripts):
    Get-ChildItem -Include *.ps1,*.psm1 -Recurse | Unblock-File -Confirm:$false

    # Then just run the script!
    .\Install-DeveloperFix.ps1

    # (Optionally, you can revert to your original Execution Policy after the installation.) 
    Set-ExecutionPolicy -ExecutionPolicy Restricted
    # Note: ExecutionPolicies are not true security boundaries.  Most "serious" PowerShell
    # users will find that leaving the execution policy set to "Restricted" is impractcal at best.
    ```

By default the script reserves the IP address range 172.16.0.0/12 for use by your coporate network.  You can use optional parameters to the script
to reserve the 192.168.0.0/16 range, or a different single range, of your choosing.

Help is available though the usual PowerShell syntax:

```powershell
# Simple Help:
.\Install-DeveloperFix.ps1 -?

# Full Help:
Get-Help .\Install-DeveloperFix.ps1 --Full
```

## Background information

### Hyper-V?  WSL?  What do I do with these?

Linux developers who choose (or are forced) to use Windows will benefit greatly
from the use the the Windows Subsystem for Linux, and the Hyper-V virtualization
engine.  These are powerful tools that enable developers (and other IT pros
such as systems administrators and analysts) to run Linux operating systems, tools, and
containers quickly and efficiently, while still having access to the broad base of
Windows productivity tools.

### Great! So what is the problem?

Unfortunately, these tools often run into problems with corporate use of
private network ranges, especially when the developer using the system roams
between remote and on-site work, or needs a VPN connection.

The comes from Hyper-V selecting private network ranges for internal use based
on the networks that it can "see" when the system starts up.  If the private networks
in use change after startup, there may be a network collision.  Networking inside
the Hyper-V and WSL VMs then fail, and sometimes general networking on the host
Windows system deteriorates as well.  Microsoft does not appear to be interested in
fixing this common problem.

### So what can I do about that?  Get a Mac?

Sure, you could get a Mac, or install Ubuntu.  You also could use an alternative Linux
run environment such as "Oracle VirtualBox", or VMware Workstation.  OR... you can just
run the "Install-DeveloperFix.ps1" script in this repository, and your life will be good again.*

This tool will install a Loopback network adapter and startup and shutdown scripts
that are designed to "trick" the Hyper-V (and WSL) network collision avoidance
algorithm into using a network range of our choosing that we know will not collide
with our corporate internal private networks.

I have experimented with muliple alternative solutions to this problem.
Only the approach in this script appears to work across multiple reboots of the system.

*Ongoing life goodness not guaranteed.
