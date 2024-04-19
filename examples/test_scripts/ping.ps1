<#
    .SYNOPSIS
        Test availability of remote host by pinging

    .DESCRIPTION
        The ping.ps1 script tests the availability of a remote host via ping (ICMP echo/reply), utilizing the Test-Connection parameter

    .PARAMETER Target
        Remote host we wish to test.  Required.

    .PARAMETER MaxTries
        Number of attempts to make before reporting failure. Default=5

    .PARAMETER TimeOutSeconds
        Amount of time (in seconds) before a ping is considered to have "failed". Passed to Test-Connection. Default=1.

    .PARAMETER SleepSeconds
        Amount of time (in seconds) between tries. Default=5

    .PARAMETER MonitorObject
        Object with monitor data passed to function by wrapper script.
#>
[CmdletBinding()]
Param
(
    [Parameter(Mandatory=$True,ValueFromPipeLineByPropertyName=$True)]
    [string]
    $Target,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]
    $MaxTries=10,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]
    $TimeOutSeconds=1,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]$SleepSeconds=5,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [switch]$Quiet,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    $MonitorObject
)

BEGIN
{
    # Set ErrorActionPreference to stop for Try/Catch
    $ErrorActionPreference="Stop"

    # Dot source functions and set test name
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

    # Calculate total seconds for status message
    $TotalSeconds = $MaxTries*$TimeOutSeconds + $($MaxTries-1)*$SleepSeconds
    
    # State
    $Tries = 0
    $Success = $False

    If(-not($Quiet)){Write-Host "($($TestName)) Pinging host: $($Target)..." -NoNewLine}
    Write-Verbose ""

    # Loop for configurable retries
    While( ($Tries++ -lt $MaxTries) -and !$Success) {
        Try {
            Write-Verbose "Attempt #$($Tries)"
            $Ping_Result = (Test-Connection -TimeoutSeconds $TimeOutSeconds -TargetName $Target -Count 1 -WA "SilentlyContinue").Status
            If($Ping_Result -eq "Success") {
                $Success=$True
                Break
            }
            ElseIf($Tries -lt $MaxTries) { 
                Write-Verbose "Failed, sleeping for $Sleep seconds"
                Start-Sleep $SleepSeconds
            }
        }
        Catch {
            Start-Sleep $SleepSeconds
            Continue
        }
    }

    # Set status/message to return to wrapper function
    If($Success) {
        $Status     = "OK"
        $Message    = "Host $($Target) is pingable."
        If(-not($Quiet)) {Write-Status $Status}
    }
    Else {
        $Status     = "DOWN"
        $Message    = "Host $($Target) is not pingable after $($MaxTries) tries and ~$($TotalSeconds) seconds."
        If(-not($Quiet)) {
            Write-Status -Error $Status
            Write-Host "(PING) $Message"
        }
    }

    # Extend monitor object to return to wrapper function
    If($MonitorObject) {
        Add-Member -InputObject $MonitorObject -MemberType "NoteProperty" -Name "CurrentStatus" -Value $Status
        Add-Member -InputObject $MonitorObject -MemberType "NoteProperty" -Name "Message" -Value $Message
        Return $MonitorObject
    }

}
