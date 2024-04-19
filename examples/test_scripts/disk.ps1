<#
    .SYNOPSIS
        Test available disk space on a host.

    .DESCRIPTION
        The disk.ps1 script tests the available disk space on a remote host.

        Requires WinRM permissions and 'Enable Account' and 'Remote Enable'
        WMI permissions on root\cimv2 namespace.

        MaxTries and Sleep set to low values 1 since we default to fast fail
        if Remote machine can't be checked.

    .PARAMETER Target
        Remote host we wish to test.  Required.

    .PARAMETER Threshold
        Percentage of used disk space to raise alarm at.

    .PARAMETER Drive
        Drive to check.  Default=C

    .PARAMETER MaxTries
        Amount of attempts before triggering an error. Default=3

    .PARAMETER Sleep
        Amount of time (in seconds) between tries. Default=15
#>
[CmdletBinding()]
Param
(
    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [string]
    $Target,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]
    $Threshold=90,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [string[]]
    $Drive="C",

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]
    $MaxTries=3,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    $Sleep=15,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [switch]$Quiet,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    $MonitorObject
)

BEGIN
{

    # Set EAP for try/catch
    $ErrorActionPreference="Stop"

    # Dot source functions
    If($PSScriptRoot) {
        # Implies this was run as standalone
        $ParentDir = (Get-Item $PSScriptRoot).Parent
        $Functions = Join-Path $ParentDir "functions.ps1"
        . $Functions

        # Get test name if run directly
        $TestName = $MyInvocation.MyCommand.Name.Replace(".ps1","").ToUpper()
    }
    ElseIf($env:_MonScriptPath) {
        # Implies this was run via wrapper
        . "$($env:_MonScriptPath)\functions.ps1"
    }

    $ThresholdString = "{0:P}" -f ($Threshold/100)

    $FQDN = ($env:COMPUTERNAME + "." + $env:USERDNSDOMAIN).ToLower()


}


PROCESS
{

    # If passed the monitor object and previous status is down, reset sleep/max tries and fail quicker
    # Also set test name since it won't be captured by MyInvocation
    If($MonitorObject) {
        If($MonitorObject.PreviousStatus -ne "OK") {
            $SleepSeconds = 0
            $MaxTries = 1
        }
        $TestName = $MonitorObject.Test_Script.ToUpper()
    }
    Else {
        Write-Host "Do NOT have MonitorObject in PROCESS"
    }

    $Tries = 0
    $Success = $False
    


    $IsLocal=$False
    If($Target.ToLower() -eq $FQDN -or $Target.ToLower() -eq $env:COMPUTERNAME) {
        $IsLocal=$True
    }

    If(-not($Quiet)) {Write-Host "($($TestName)) Checking disk space for $($Drive) on host: $($Target)..." -NoNewLine}
    While( ($Tries++ -lt $MaxTries) -and !$Success) {
        Try {
            If($IsLocal) {
                $DriveInfo = Invoke-Command -ScriptBlock { Param($Drive) Get-PSDrive $Drive } -Args $Drive
            }
            Else {
                $DriveInfo = Invoke-Command -ComputerName $Target -ScriptBlock { Param($Drive) Get-PSDrive $Drive } -Args $Drive
            }
            $Success=$True
        }
        Catch {
            Start-Sleep $Sleep
        }
    }

    If($DriveInfo) {
        $Used = $DriveInfo.Used
        $Free = $DriveInfo.Free
        $Total = $Used+$Free
        $PercentUsed = "{0:P}" -f ($Used/$Total)
        If($PercentUsed -gt $Threshold) {
            $Problem=$True
        }

    }

    If($Success -and !$Problem) {
        If(-not($Quiet)) {Write-Status "OK"}
        $Status="OK"
        $Message="Disk space usage OK ($($PercentUsed) < $($ThresholdString)) for $($Drive): on $($Target)"
    }
    ElseIf(!$Success) {
        If(-not($Quiet)) {Write-Status -Error "ERROR"} 
        $Status="ERROR"
        $Message="Cannot check drive status for $Drive on $Remote_Host"
    }
    Else {
        If(-not($Quiet)) {Write-Status -Error "PROBLEM"} 
        $Status="PROBLEM"
        $Message = "Disk space usage $PercentUsed (> $ThresholdString ) for $($Drive): on $($Remote_Host)"
    }

    If(-not($Quiet)) {Write-Host "($($TestName)) $($Message)"}

    # Extend monitor object to return to wrapper function
    If($MonitorObject) {
        Add-Member -InputObject $MonitorObject -MemberType "NoteProperty" -Name "CurrentStatus" -Value $Status
        Add-Member -InputObject $MonitorObject -MemberType "NoteProperty" -Name "Message" -Value $Message
        Return $MonitorObject
    }

}