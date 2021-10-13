#########################################################################
# From: <https://github.com/skorhone/wsl2-custom-network/blob/main/hcn/Hcn.psm1>

function Get-HnsClientNativeMethods() {
        $signature = @'
        // Networks
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnEnumerateNetworks(
            [MarshalAs(UnmanagedType.LPWStr)]
            string Query,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Networks,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnCreateNetwork(
            [MarshalAs(UnmanagedType.LPStruct)]
            Guid Id,
            [MarshalAs(UnmanagedType.LPWStr)]
            string Settings,
            [MarshalAs(UnmanagedType.SysUInt)]
            out IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnOpenNetwork(
            [MarshalAs(UnmanagedType.LPStruct)]
            Guid Id,
            [MarshalAs(UnmanagedType.SysUInt)]
            out IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnModifyNetwork(
            [MarshalAs(UnmanagedType.SysUInt)]
            IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            string Settings,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnQueryNetworkProperties(
            [MarshalAs(UnmanagedType.SysUInt)]
            IntPtr Network,
            [MarshalAs(UnmanagedType.LPWStr)]
            string Query,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Properties,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnDeleteNetwork(
            [MarshalAs(UnmanagedType.LPStruct)]
            Guid Id,
            [MarshalAs(UnmanagedType.LPWStr)]
            out string Result);
 
        [DllImport("computenetwork.dll")]
        public static extern System.Int64 HcnCloseNetwork(
            [MarshalAs(UnmanagedType.SysUInt)]
            IntPtr Network);
'@

    # Compile into runtime type
    Add-Type -MemberDefinition $signature -Namespace ComputeNetwork.HNS.PrivatePInvoke -Name NativeMethods -PassThru
}

Add-Type -TypeDefinition @"
    public enum ModifyRequestType {
        Add,
        Remove,
        Update,
        Refresh
    };
 
    public enum EndpointResourceType {
        Port,
        Policy,
    };
    public enum NetworkResourceType {
        DNS,
        Extension,
        Policy,
        Subnet,
        Subnets,
        IPSubnet
    };
    public enum NamespaceResourceType {
    Container,
    Endpoint,
    };
"@

$ClientNativeMethods = Get-HnsClientNativeMethods

$NetworkNativeMethods = @{
    Open = $ClientNativeMethods::HcnOpenNetwork;
    Close = $ClientNativeMethods::HcnCloseNetwork;
    Enumerate = $ClientNativeMethods::HcnEnumerateNetworks;
    Delete = $ClientNativeMethods::HcnDeleteNetwork;
    Query = $ClientNativeMethods::HcnQueryNetworkProperties;
    Modify = $ClientNativeMethods::HcnModifyNetwork;
}

#########
# Network

function New-HnsNetworkEx {
    param (
        [parameter(Mandatory=$true)] [Guid] $Id,
        [parameter(Mandatory=$true, Position=0)]
        [string] $JsonString
    )

    $settings = $JsonString
    $handle = 0
    $result = ""
    $hnsClientApi = Get-HnsClientNativeMethods
    $hr = $hnsClientApi::HcnCreateNetwork($id, $settings, [ref] $handle, [ref] $result);
    ReportErrorsEx -FunctionName HcnCreateNetwork -Hr $hr -Result $result -ThrowOnFail

    $query =  '{"SchemaVersion": { "Major": 1, "Minor": 0 }}'
    $properties = "";
    $result = ""
    $hr = $hnsClientApi::HcnQueryNetworkProperties($handle, $query, [ref] $properties, [ref] $result);
    ReportErrorsEx -FunctionName HcnQueryNetworkProperties -Hr $hr -Result $result
    $hr = $hnsClientApi::HcnCloseNetwork($handle);
    ReportErrorsEx -FunctionName HcnCloseNetwork -Hr $hr

    return ConvertResponseFromJsonEx -JsonInput $properties
}

function Get-HnsNetworkEx {
    param (
        [parameter(Mandatory=$false)] [Guid] $Id = [Guid]::Empty,
        [parameter(Mandatory=$false)] [switch] $Detailed,
        [parameter(Mandatory=$false)] [int] $Version
    )
    if($Detailed.IsPresent) {
        return Get-HnsGenericEx -Id $Id -NativeMethods $NetworkNativeMethods -Version $Version -Detailed
    }
    else {
        return Get-HnsGenericEx -Id $Id -NativeMethods $NetworkNativeMethods -Version $Version
    }
}

function Remove-HnsNetworkEx {
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
        [Object[]] $InputObjects
    )
    begin {$objects = @()}
    process {$Objects += $InputObjects;}
    end {
        Remove-HnsGenericEx -InputObjects $Objects -NativeMethods $NetworkNativeMethods
    }
}

#########
# Generic

function Get-HnsGenericEx {
    param (
        [parameter(Mandatory=$false)] [Guid] $Id = [Guid]::Empty,
        [parameter(Mandatory=$false)] [Hashtable] $Filter = @{},
        [parameter(Mandatory=$false)] [Hashtable] $NativeMethods,
        [parameter(Mandatory=$false)] [switch]    $Detailed,
        [parameter(Mandatory=$false)] [int]       $Version
    )
    
    $ids = ""
    $FilterString = ConvertTo-Json $Filter -Depth 32
    $query = @{Filter = $FilterString }
    if($Version -eq 2) {
        $query += @{SchemaVersion = @{ Major = 2; Minor = 0 }}
    }
    else {
        $query += @{SchemaVersion = @{ Major = 1; Minor = 0 }}
    }
    if($Detailed.IsPresent) {
        $query += @{Flags = 1}
    }
    $query = ConvertTo-Json $query -Depth 32
    if ($Id -ne [Guid]::Empty) {
        $ids = $Id
    }
    else {
        $result = ""
        $hr = $NativeMethods["Enumerate"].Invoke($query, [ref] $ids, [ref] $result);
        ReportErrorsEx -FunctionName $NativeMethods["Enumerate"].Name -Hr $hr -Result $result -ThrowOnFail

        if($ids -eq $null) {
            return
        }

        $ids = ($ids | ConvertFrom-Json)
    }
    
    $output = @()
    $ids | ForEach-Object {
        $handle = 0
        $result = ""
        $hr = $NativeMethods["Open"].Invoke($_, [ref] $handle, [ref] $result);
        ReportErrorsEx -FunctionName $NativeMethods["Open"].Name -Hr $hr -Result $result
        $properties = "";
        $result = ""
        $hr = $NativeMethods["Query"].Invoke($handle, $query, [ref] $properties, [ref] $result);
        ReportErrorsEx -FunctionName $NativeMethods["Query"].Name -Hr $hr -Result $result
        $output += ConvertResponseFromJsonEx -JsonInput $properties
        $hr = $NativeMethods["Close"].Invoke($handle);
        ReportErrorsEx -FunctionName $NativeMethods["Close"].Name -Hr $hr
    }

    return $output
}

function Remove-HnsGenericEx {
    param (
        [parameter(Mandatory = $false, ValueFromPipeline = $True, ValueFromPipelinebyPropertyName = $True)]
        [Object[]] $InputObjects,
        [parameter(Mandatory=$false)] [Hashtable] $NativeMethods
    )

    begin {$objects = @()}
    process {
        if($InputObjects) {
            $Objects += $InputObjects;
        }
    }
    end {
        $Objects | Foreach-Object {
            $result = ""
            $hr = $NativeMethods["Delete"].Invoke($_.Id, [ref] $result);
            ReportErrorsEx -FunctionName $NativeMethods["Delete"].Name -Hr $hr -Result $result
        }
    }  
}

#########
# Helpers

function ReportErrorsEx {
    param (
        [parameter(Mandatory=$false)]
        [string] $FunctionName,
        [parameter(Mandatory=$true)]
        [Int64] $Hr,
        [parameter(Mandatory=$false)]
        [string] $Result,
        [switch] $ThrowOnFail
    )

    $errorOutput = ""

    if($Hr -ne 0) {
        $errorOutput += "HRESULT: $($Hr). "
    }

    if(-NOT [string]::IsNullOrWhiteSpace($Result)) {
        $errorOutput += "Result: $($Result)"
    }

    if(-NOT [string]::IsNullOrWhiteSpace($errorOutput)) {
        $errString = "$($FunctionName) -- $($errorOutput)"
        if($ThrowOnFail.IsPresent) {
            throw $errString
        }
        else {
            Write-Error $errString
        }
    }
}

function ConvertResponseFromJsonEx {
    param (
        [parameter(Mandatory=$false)]
        [string] $JsonInput
    )

    $output = "";
    if ($JsonInput) {
        try {
            $output = ($JsonInput | ConvertFrom-Json);
        } catch {
            Write-Error $_.Exception.Message
            return ""
        }
        if ($output.Error) {
             Write-Error $output;
        }
    }

    return $output;
}

