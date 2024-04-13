<#
    .SYNOPSIS
        Test availability of remote website.

    .DESCRIPTION
        The http.ps1 script tests the availability of a remote host via the Invoke-WebRequest cmdlet.

    .PARAMETER Target
        Remote host we wish to test.  Required.

    .PARAMETER Resource
       Resource we wish to test. Defaults to root of host (/) but can be a subdirectory or file.

    .PARAMETER Protocol
        Protocol we wish to use (http, https). Default is HTTPS.

    .PARAMETER Port
        Port we wish to use.  Default is default for protocol (80,443).

    .PARAMETER Keyword
        Return OK if given keyword found in response.

    .PARAMETER JSONAttribute
        Return OK if given JSON Attribute found in response.

    .PARAMETER JSONValue
        Return OK if given JSON Value for JSONAttribute found in response.

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
    [string]
    $Resource="/",

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [ValidateSet("http","https")]
    [string]
    $Protocol="https",

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]
    $Port,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [string]
    $Keyword,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [string]
    $JSONAttribute,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [string]
    $JSONValue,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [switch]
    $UseDefaultCredentials,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]$MaxTries=10,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]$TimeOutSeconds=1,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [int]
    $SleepSeconds=5,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    [switch]
    $Quiet,

    [Parameter(Mandatory=$False,ValueFromPipeLineByPropertyName=$True)]
    $MonitorObject
)

BEGIN
{
    # Set ErrorActionPreference to stop for Try/Catch
    $ErrorActionPreference="Stop"

    # Dot source functions
    If($env:_MonScriptPath) {
        # Implies this was run via wrapper
        . "$($env:_MonScriptPath)\functions.ps1"
    }
    ElseIf($PSScriptRoot) {
        # Implies this was run as standalone
        $ParentDir = (Get-Item $PSScriptRoot).Parent
        $Functions = Join-Path $ParentDir "functions.ps1"
        . $Functions

        # Get test name if run directly
        $TestName = $MyInvocation.MyCommand.Name.Replace(".ps1","").ToUpper()
    }
}

PROCESS
{

    # If passed the monitor object and previous status is down, reset sleep/max tries and fail quicker
    If($MonitorObject) {
        If($MonitorObject.PreviousStatus -eq "DOWN") {
            $SleepSeconds = 0
            $MaxTries = 1
        }
    }

    # Calculate total seconds for status message
    $TotalSeconds = $MaxTries*$TimeOutSeconds + $($MaxTries-1)*$SleepSeconds
    
    # Internal State
    $Tries = 0
    $Success = $False
    $Message = $NULL

    # Build URL
    # Expected use case is that target is hostname, but handle target being URL
    If($Target -like "http://*") {
        $Protocol = "http"
        $Target = $Target.Replace("http://","")
    }
    If($Target -like "https://*") {
        $Protocol = "https"
        $Target = $Target.Replace("https://","")
    }
    If($Target -like "*/*") {
        $Split = $Target.Split("/")
        $Len = $Split.Length
        $Target = $Split[0]
        $Resource = "/" + $Split[1..$($Len-1)]
    }
    If($Target -like "*:*") {
        Write-Verbose "Ignoring port"
        $Port=$Null
    }
    
    If($Resource -notlike "/*") {
        $Resource = "/" + $Resource
    }
    Write-Verbose "Protocol: $Protocol"
    Write-Verbose "Target: $Target"
    Write-Verbose "Resource: $Resource"
    Write-Verbose "Port: $Port"
    
    $URL = "$($Protocol)://$Target"
    If($Port) { $URL+=":$($Port)" }
    If($Resource) { $URL+=$Resource }
    
    # Build message to sent to host
    $HostMessage = "(HTTP) Connecting to URL: $($URL)"
    If($UseDefaultCredentials) { $HostMessage+=" (UseDefaultCredentials set)" }
    $HostMessage+="..."

    If(-not($Quiet)) {Write-Host $HostMessage -NoNewLine}
    Write-Verbose ""
    

    # Retry loop
    While( ($Tries++ -lt $MaxTries) -and !$Success) {
        Try {
            Write-Verbose "Attempt #$($Tries)"
            $HTTP_Result = Invoke-WebRequest -Uri $URL -AllowInsecureRedirect -NoProxy -UseDefaultCredentials:$UseDefaultCredentials.IsPresent
            $HTTP_Status = $HTTP_Result.StatusCode

            # Check for Status=200
            If($HTTP_Status -eq "200") {
                # Begin building message
                $Message="URL $URL is accessible. Status Code=200."
                Write-Verbose $Message

                # If we have Keyword parameter, check for keyword in content
                If($Keyword) {
                    If($HTTP_Result.Content -contains $Keyword) {
                        $Success=$True
                        $ThisMessage="Keyword found in response: $($Keyword)."
                        $Message+=" $($ThisMessage)"
                        Write-Verbose $ThisMessage
                    }
                    Else {
                        $Success=$False
                        $ThisMessage="Keyword NOT found in response: $($Keyword)."
                        $Message+=" $($ThisMessage)"
                        Write-Verbose $ThisMessage
                    }
                }

                # Else if we have JSONAttribute parameter, check for JSON
                ElseIf($JSONAttribute) {
                    Try {
                        $JSON = $HTTP_Result.Content|ConvertFrom-JSON
                        If($JSON.$JSONAttribute) {
                            $ThisMessage="JSON Attribute $JSONAttribute found."
                            $Message+=" $($ThisMessage)"

                            # If specific value specified, check that
                            If($JSONValue) {
                                If($JSON.$JSONAttribute -eq $JSONValue) {
                                    $Success=$True
                                    $ThisMessage="Expected Value=$($JSONValue), Found Value=$($JSON.$JSONAttribute)"
                                    $Message+=" $($ThisMessage)"
                                    Write-Verbose $ThisMessage
                                    Break
                                }
                                Else {
                                    $Success=$False
                                    $ThisMessage="Expected Value=$($JSONValue), Found Value=$($JSON.$JSONAttribute)"
                                    $Message+=" $($ThisMessage)"
                                    Write-Verbose $ThisMessage
                                }
                            }
                            Else {
                                $Success=$True
                                Break
                            }
                        }
                        Else {
                            $Success=$False
                            $ThisMessage="JSON Attribute $($JSONAttribute) not present in response."
                            $Message+=" $($ThisMessage)"
                            Write-Verbose $ThisMessage
                        }
                    }
                    Catch {
                        $Success=$False
                        $ThisMessage="Error converting response to JSON: $($_.Exception.Message)."
                        $Message+=" $($ThisMessage)"
                        Write-Verbose $ThisMessage
                    }
                }

                # If neither Header, JSONAttribute, or Keyword specified, and we have 200, this is successful
                Else {
                    $Success=$True
                    Break
                }
            }
            ElseIf($Tries -lt $MaxTries) { 
                Write-Verbose "Failed, sleeping for $Sleep seconds"
                Start-Sleep $SleepSeconds
            }
        }
        Catch {
            $LastException = $_
            Write-Verbose "Caught error"
            Start-Sleep $SleepSeconds
            Continue
        }
    }

    # Set status/message to return to wrapper function
    If($Success) {
        $Status     = "OK"
        If(-not($Quiet)) {Write-Status $Status}
    }
    Else {
        $Status     = "DOWN"
        If(-not($Message)) {
            # No message indicates we've hit an exception several times
            $Message = "URL $URL is not accessible after $MaxTries tries and ~$($TotalSeconds) seconds. LastError=($($LastException.Exception.Message))"
        }
        If(-not($Quiet)) {
            Write-Status -Error $Status
            Write-Host "(HTTP) $Message"
        }
    }

    
    # Extend monitor object to return to wrapper function
    If($MonitorObject) {
        Add-Member -InputObject $MonitorObject -MemberType "NoteProperty" -Name "CurrentStatus" -Value $Status
        Add-Member -InputObject $MonitorObject -MemberType "NoteProperty" -Name "Message" -Value $Message
        Return $MonitorObject
    }
    
}
