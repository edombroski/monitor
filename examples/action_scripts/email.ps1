[CmdletBinding()]
Param
(
    $Monitor="Default_Monitor",
    $EmailTo,
    $EmailFrom,
    $SMTPServer,
    $Test="Random_Test",
    $Current_Status="OK",
    $Message="Email Action Script Default Message",
    $MonitorObject
)

BEGIN
{
    # Set ErrorActionPreference to stop for Try/Catch
    $ErrorActionPreference="Stop"

    # Get action name. May not set if called via scriptblock
    $ActionName = $MyInvocation.MyCommand.Name.Replace(".ps1","").ToUpper()

    # Dot source config&functions
    If($env:_MonScriptPath) {
        # Implies this was run via wrapper
        . "$($env:_MonScriptPath)\config.ps1"
        . "$($env:_MonScriptPath)\functions.ps1"
    }
    ElseIf($PSScriptRoot) {
        # Implies this was run as standalone
        $ParentDir = (Get-Item $PSScriptRoot).Parent
        $Config    = Join-Path $ParentDir "config.ps1"
        $Functions = Join-Path $ParentDir "functions.ps1"
        . $Config
        . $Functions


    }
}

PROCESS
{

    If(-not($EmailTo)) { $EmailTo = $DefaultEmailTo     }
    If(-not($EmailFrom)) { $EmailFrom = $DefaultEmailFrom   }
    If(-not($SMTPServer)) { $SMTPServer = $DefaultSMTPServer  }

    Write-Host "($($ActionName))`tEmailTo: $EmailTo, EmailFrom: $EmailFrom, SMTPServer: $SMTPServer, Message: $Message, Current_Status: $Current_Status"

    If($Current_Status -eq "OK") {
        $SubjectPrefix = "CLEARED"
    }
    Else {
        $SubjectPrefix = "ALERT"
    }


    $MaxTries=5
    $Tries=0

    $ErrorActionPreference="Stop"
    $SendTo = $EmailTo.Split(";")
    $Success=$False
    While($Tries -lt $MaxTries) {
        Try {
            $Subject = "$($SubjectPrefix): $($Monitor) Test=$($Test) Status=$($Current_Status)"
            If($Message) { $Body=$Message }
            Else { $Body = $Subject }
            Write-Host "($($ActionName))`tSubject: $($Subject)"
            Write-Host "($($ActionName))`tBody: $($Body)"
            Send-MailMessage `
                -WarningAction "SilentlyContinue" `
                -To $EmailTo `
                -From $EmailFrom `
                -Subject $Subject `
                -Body $Body `
                -SmtpServer $SMTPServer 

            $Success=$True
            Break
            #Return "Emailed $($to) about $($Display_Name). Current State=$($Current_State)"
        }

        Catch {
            $Tries++
            Start-Sleep 15
            Continue
            $LastException = $_
        }
    }

    If(-not($Success)) {
        Return "Error sending email: $($LastException.Exception.Message)"
    }

}