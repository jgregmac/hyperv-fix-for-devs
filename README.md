# Hyper-V and WSL2 Network Fix for Linux Developers

## Hyper-V?  WSL?  What do I do with these?

Linux developers who choose (or are forced) to use Windows will benefit greatly
from the use the the Windows Subsystem for Linux, and the Hyper-V virtualization
engine.  These are amazingly powerfull tools that enable developers (and other IT pros
such as systems administrators and analysts) to run Linux operating systems, tools, and
containers quickly and efficiently, while still having access to the broad base of
Windows productivity tools.

## Great! So what is the problem?

Unfortunately, these tools often run into problems with corporate use of
private network ranges, especially when the developer using the system roams
between remote and on-site work, or needs a VPN connection.

The comes from Hyper-V selecting private network ranges for internal use based
on the networks that it can "see" when the system starts up.  If the private networks
in use change after startup, there may be a network collision.  Networking inside
the Hyper-V and WSL VMs then fail, and sometimes general networking on the host
Windows system deteriorates as well.  Microsoft does not appear to be interested in
fixing this common problem.

## So what can I do about that?  Get a Mac?

Sure, you could get a Mac, or install Ubuntu.  OR... you can just run the
"Install-DeveloperFix.ps1" script in this repository, and your life will be good again.*

This tool will install a Loopback network adapter and startup and shutdown scripts
that are designed to "trick" the Hyper-V (and WSL) network collision avoidance
algorithm into using a network range of our choosing that we know will not collide
with our corporate internal private networks.

I have experimented with muliple alternative solutions to this problem.
Only the approach in this script appears to work across multiple reboots of the system.

*Ongoing life goodness not guaranteed.
