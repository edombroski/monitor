# Configurations for folders
If($env:_MonScriptPath) {
    $ScriptRoot = $env:_MonScriptPath
}
Else {
    $ScriptRoot = $PSScriptRoot
}

. "$($ScriptRoot)\config.ps1"

## VERY BASIC FUNCTIONS ##
# In process of porting over better ones

Function Write-Status
{
    <#
        .SYNOPSIS
            Write a simple status message in formatted text.
    #>
    Param
    (
        [string]$Status,
        [switch]$Error
    )

    If($Error) { $Color = "Red" }
    Else { $Color = "Blue" }
    Write-Host -ForegroundColor "White" -NoNewLine "["
    Write-Host -ForegroundColor $Color -NoNewLine $Status
    Write-Host -ForegroundColor "White" "]"
}


Function Write-LogHost
{
    <#
        .SYNOPSIS
            Write to the host and also to a log file.
        .DESCRIPTION
            Not MP safe! Do not use in test scripts when MP mode enabled!
    #>
    Param
    (
        $Message,
        [switch]$Warning,
        [switch]$StatusChange,
        $ForegroundColor
    )

    If(-not(Test-Path $LogFile)) {
        New-Item -Force $LogFile|Out-Null
    }
    If(-not(Test-Path $StatusChangesLogFile)) {
        New-Item -Force $StatusChangesLogFile|Out-Null
    }

    # Timestamp
    $ts=(Get-Date -format "yyyy.MM.dd-HH.mm.ss")

    # Log start
    "$($ts) $Message" | Out-File -Append $LogFile
    If($Warning) { Write-Warning $Message }
    ElseIf($ForegroundColor) { Write-Host $Message -Foregroundcolor $ForegroundColor }
    Else { Write-Host $Message }

    If($StatusChange) {
        "$($ts) $Message" | Out-File -Append $StatusChangesLogFile
    }

}


Function Write-ErrorMessage
{
    <#
        .SYNOPSIS
            Write error message to screen in red text and append "ERROR" to it.
        .DESCRIPTION
            Not MP safe! Don't use in tests when using MP mode!
    #>
    Param
    (
        $Message
    )

    $NewMessage = "ERROR: " + $Message
    Write-LogHost $NewMessage -ForegroundColor "Red"

}