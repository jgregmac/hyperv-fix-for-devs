param (
    # Name of the dummy adapter that will be enabled.
    [string]$AdapterName = "Hyper-V Fix"
)

$logRoot = Split-Path $script:MyInvocation.MyCommand.Path -Parent
$logfilepath = Join-Path -Path $logRoot -ChildPath EnableHyperAdapter.log

function WriteToLogFile ($message) {
   Add-content $logfilepath -value $message
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
}

WriteToLogFile "IP Config after Applying Fix:"
ipconfig | Out-File -Append -FilePath $logfilepath
