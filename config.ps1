# Configurations for folders
If($env:_MonScriptPath) {
    $ScriptRoot = $env:_MonScriptPath
}
Else {
    $ScriptRoot = $PSScriptRoot
}

$MonitorConfigFilesLocation     = "$($ScriptRoot)\monitor_configs"
$TestScriptLocation             = "$($ScriptRoot)\test_scripts"
$ActionScriptLocation           = "$($ScriptRoot)\action_scripts"
$HelperScriptLocation           = "$($ScriptRoot)\helper_scripts"
$MonitorDataLocation            = "$($ScriptRoot)\monitor_data"
$LocalConfigFileLocation        = "$($ScriptRoot)\config_local.ps1"

# Configurations for files
$LastRunFile                    = "$($ScriptRoot)\LastRun.txt"

# Repeat Action Minutes
$RepeatActionMinutes            = 12*60

# Default values for Email Action
$DefaultEmailTo                        = "nobody@localhost"
$DefaultEmailFrom                      = $env:USERNAME + "@" + $env:COMPUTERNAME
$DefaultSMTPServer                     = "127.0.0.1"

# Override configurations with local config if present
If(Test-Path $LocalConfigFileLocation) {
    . $LocalConfigFileLocation
}