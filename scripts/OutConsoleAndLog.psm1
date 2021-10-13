Function Out-ConsoleAndLog {
    <#
    .SYNOPSIS
        Writes the specifiec message to the specified log file, and to the output stream specified by -Type.
    .DESCRIPTION
        Logs to the file specified in in the -LogFile parameter, and to the output stream selected by the 
        -Type parameter.  
        Log entries will be pre-pended with a time stamp.
        If -Type is not specified, the message is only logged.
        If the -Verbose switch is provided (or if the $VerbosePreference is set to 'Continue') the function 
        also writes the message to verbose output.
        If the global variable 'GlobalLog' is defined, the path contained in that variable will be used as the 
        target for the message.
    .PARAMETER Message
        Mandatory parameter, accepts pipeline input.  
        Text string to send to log file and verbose output.
    .PARAMETER LogFile
        Optional parameter.  
        Full path to the log file to which to write output. If the LogFile is not specified, the path 
        specified in the global variable 'globalLog' will be used instead.  If 'globalLog' is not set,
        then the message will not be logged. 
    .PARAMETER Type
        Optional parameter. Specifies the type of console output to which to send the message.  
        Valid choices are "Verbose", "Host", "StdOut", "Warning", and "Error".
          - Verbose: Writes to the PowerShell Verbose output stream.  
            Use the -Verbose parameter or set the $VerbosePreference variable to display the Verbose stream.
          - StdOut (or 'Pipeline'): Writes to Standard Output.  'Pipeline' is maintained as an alias for
            backward compatibility
          - Host: Writes to the PowerShell host stream.  
            NOTE: This is not the same as standard out.  'Host' output cannot be used in a pipeline.
          - Warning: Writes to the PowerShell Warning output stream
          - Error: Writes to the PowerShell error object.  This option also throws a terminating error,
        If no choice is specified, Verbose will be used (StdOut would be more logical, but we use Verbose
        to reduce the chance of unwanted standard output causing SCCM detection failures).
    .PARAMETER Color
        Specifies the text foreground color to be used with the output type 'Host'.  If any other output
        type is specified, this parameter will be ignored.
    .EXAMPLE
        PS> "Sending Faxes!" | Out-ConsoleAndLog -LogFile 'LikeABoss.txt' -Verbose
        Writes "Sending Faxes!" to the log file "LikeABoss.txt", and sends the same text to Verbose 
        output.  Demonstrates the use of pipeline input.
    .EXAMPLE
        PS> $ErrorActionPreference = 'Continue'; 
        PS> Out-ConsoleAndLog -Message 'Creating Synergies!' -LogFile 'LikeABoss.txt'
        Writes "Creating Synergies" to the log file "LikeABoss.txt", and sends the same text to Verbose 
        output.  Demonstrates use of the variable $ErrorActionPreference to control verbose output.
    .EXAMPLE
        PS> Out-ConsoleAndLog -Type Warning -Message "No promotion!" -LogFile "LikeABoss.txt"
        Writes "No promotion!" to the warning output stream, a logs to "LikeABoss.txt"
    #>
    [cmdletBinding()]

    param(
        [parameter(Position=0,Mandatory=$True,ValueFromPipeline=$True)]
            [string]$Message,
        [parameter()]
            [string]$LogFile = $global:GlobalLog,
        [parameter()][ValidateSet('Verbose','Warning','Error','Pipeline','StdOut','Host')]
            [string]$Type = "Host",
        [parameter()][ValidateSet(
            'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 'DarkYellow', 
            'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White')]
            [string]$Color,
        [parameter(Mandatory=$False)]
            [switch]$NoDate
    )

    Process {
        if (-not $NoDate) {
            $Message = $Type + ': [' + (get-date -Format 'yyyy-MM-dd : HH:mm:ss') + '] : ' + $Message
        }
        switch ($Type) {
            ('Error')                 {Write-Error $Message -ErrorAction Continue}
            ('Warning')               {Write-Warning $Message}
            ('StdOut' -or 'Pipeline') {Write-Output $Message}
            ('Host')                  {if ($color) {Write-Host $message -Foregroundcolor $color} else {Write-Host $Message}}
            ('Verbose')               {Write-Verbose $Message}
        }
        if ($LogFile) {$Message | Out-File -FilePath $LogFile -Append}
    }
}

Export-ModuleMember -Function Out-ConsoleAndLog