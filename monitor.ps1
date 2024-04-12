[CmdletBinding()]
Param
(
    [string[]]
    $TestScriptsToRun,

    [string[]]
    $TestCategoriesToRun,

    [string[]]
    $Targets,

    [string[]]
    $TargetsToSkip,

    [switch]
    $DontRunActionScript,

    [switch]
    $OnlyDown,

    [switch]
    $OnlyUp, 

    [switch]
    $Quiet

)

# Get start time for end statistics
$StartTime = Get-Date

# Load script config (for file location, etc.)
. "$($psscriptroot)\config.ps1"

# Get monitor configuration .csv files
$MonitorConfigFiles = Get-ChildItem $MonitorConfigFilesLocation

# Create arraylist for ThingsToMonitor
$ThingsToMonitor = New-Object System.Collections.ArrayList

# Go through config files to look for things to monitor
Foreach($MonitorConfigFile in $MonitorConfigFiles) {

    # Create category name from filename (replace underscores with spaces)
    $Category = $MonitorConfigFile.Name.Replace("_"," ").Replace(".csv","").Trim()

    # Skip -TestCategoriesToRun parameter provided, and the category is not in the list
    If($TestCategoriesToRun) {
        If($TestCategoriesToRun -notcontains $Category) { Continue }
    }

    # Import the CSV of tests
    $CSV = Import-CSV $MonitorConfigFile

    # Create hash table to store monitor names
    $MonitorNamesHash = @{}

    # Go through things to monitor
    Foreach($ThingToMonitor in $CSV) {

        # Skip if -TestScriptsToRun parameter provided, and the test is not in this list
        If($TestScriptsToRun) {
            If($TestScriptsToRun -notcontains $ThingToMonitor.Test_Script) { Continue }
        }

        # Skip if -Targets parameter provided, and the target is not in this list
        If($Targets) {
            If($Targets -notcontains $ThingToMonitor.Target) { Continue }
        }

        # Skip if -TargetsToSkip parameter provided, and the target is not in this list
        If($TargetsToSkip) {
            If($TargetsToSkip -contains $ThingToMonitor.Target) { Continue }
        }

        # To prevent possible syntax errors down the line, parse properties in variables and trim them
        $Monitor_Name   = $ThingToMonitor.Monitor_Name.Trim()
        $Target         = $ThingToMonitor.Target.Trim()
        $Test_Script    = $ThingToMonitor.Test_Script.Trim()
        $Test_Params    = $ThingToMonitor.Test_Params.Trim()
        $Action_Script  = $ThingToMonitor.Action_Script.Trim()
        $Action_Params  = $ThingToMonitor.Action_Params.Trim()
        $Options        = $ThingToMonitor.Options.Trim()

        # Start with our two main options set to False
        $MaintenanceMode        = $False
        $AlwaysInvokeAction     = $False

        # Determine script options
        If($Options) {
            $MonitorOptions = $Options.Split(",")
            Foreach($MonitorOption in $MonitorOptions) {
                $MonitorOptionName, $MonitorOptionValue = $MonitorOption.Split("=")
                Switch($MonitorOptionName)
                {
                    "MAINTENANCE_MODE" {
                        $MaintenanceMode=[bool]$MonitorOptionValue
                    }
                    "REPEAT_ACTION_MINUTES"
                    {
                        $RepeatActionMinutes=$MonitorOptionValue
                    }
                    "ALWAYS_INVOKE_ACTION"
                    {
                        $AlwaysInvokeAction=[bool]$MonitorOptionValue
                    }
                    default {
                        Write-Warning "Unrecognized option name $MonitorOptionName, skipping"
                    }
                }
            }
        }

        # If no Monitor_Name, we likely have a blank line. Skip
        If(-not($Monitor_Name)) { Continue }

        # Use highly-unlikely-to-be-used unicode 'double-underscore' character to replace actual underscores in test names
        # These files names are replaced back by future status gathering function
        $NormalizedCategoryName = $Category.Replace(" ","_")
        $NormalizedMonitorName  = $Monitor_Name.Replace("_",[regex]::unescape("\u2017")).Replace(" ","_")

        # Use previously created hashtable to keep track of datafile names/locations since we can have
        # Multiple tests in the same category/file with the same monitor name
        If($MonitorNamesHash[$NormalizedMonitorName]) {
            $Count          = ++$MonitorNamesHash[$NormalizedMonitorName]
            $CountStr       = "{0:d2}" -f 0
            $DataDir        = "$($MonitorDataLocation)\$($NormalizedCategoryName)\$($NormalizedMonitorName)_$($CountStr)"
            $StatusFile     = Join-Path $DataDir "status.xml"
        }
        Else {
            $DataDir        = "$($MonitorDataLocation)\$($NormalizedCategoryName)\$($NormalizedMonitorName)_01"
            $StatusFile     = Join-Path $DataDir "status.xml"
            $MonitorNamesHash.Add($NormalizedMonitorName,1)
        }

        # If status file exists, get previous status
        # Otherwise, create the status file and parent directory structure (-Force)
        # Set initial status of "INIT"
        If(Test-Path $StatusFile) {
            $PreviousStatus = (Import-CLIXML $StatusFile)."Status"
        }
        Else {
            If(-not($Quiet)){Write-Host "Creating status file $StatusFile"}
            New-Item -Type File $StatusFile -Force | Out-Null
            $PreviousStatus = "INIT"
            $StatusObject = [pscustomobject]@{
                "Status"="INIT"
            }
            $StatusObject|Export-CLIXML $StatusFile
        }

        # If Maintenance Mode option set for this test, set that as status then skip
        If($MaintenanceMode) {
            If($PreviousStatus -ne "MAINT") {
                $StatusObject = [pscustomobject]@{
                    "Status"="MAINT"
                }
                $StatusObject|Export-CLIXML $StatusFile
            }
            Continue
        }

        # If -OnlyDown parameter specified, only run script if previous status is not OK
        # Thus if previous state is INIT or OK, skip
        If($OnlyDown) {
            If($PreviousStatus -in @("OK","INIT")) { Continue }
        }

        # If -OnlyUp parameter specified, only run script if previous status is not OK
        # Thus if previous state !OK, skip
        If($OnlyUp) {
            If($PreviousStatus -ne "OK") { Continue }
        }

        # We want to pass an object via the pipeline to a test script
        # Build TestProperties hashtable to hold all the properties
        $TestProperties=@{}

        # Add the Target (required parameter)
        $TestProperties.Add("Target",$ThingToMonitor.Target)

        # If -Quiet passed, add parameter
        If($Quiet) {
            $TestProperties.Add("Quiet",$True)
        }

        # For each provided Test parameter, add that as well
        If($Test_Params) {
            $Test_Params = $Test_Params.Split(",")
            Foreach($Test_Param in $Test_Params) {
                $Test_Param_Name, $Test_Param_Value = $Test_Param.Split("=")
                
                # Special case for booleans for switches
                If($Test_Param_Value -eq "True") {
                    Write-Verbose "Test param value True"
                    $TestProperties.Add($Test_Param_Name, $True)
                }
                ElseIf($Test_Param_Value -eq "False") {
                    Write-Verbose "Test param value False"
                    $TestProperties.Add($Test_Param_Name, $True)
                }
                Else {
                    $TestProperties.Add($Test_Param_Name, $Test_Param_Value)
                }
            }
        }

        # Do the same for action scripts
        $ActionProperties=@{}
        If($ThingToMonitor.Action_Params) {
            $Action_Params = $Action_Params.Split(",")
            Foreach($Action_Param in $Action_Params) {
                $Action_Param_Name, $Action_Param_Value = $Action_Param.Split("=")
                $ActionProperties.Add($Action_Param_Name, $Action_Param_Value.Split(";"))
            }
        }

        # Extend the CSV "Thing To Monitor" object with these properties
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "Test_Script_Properties" -Value $TestProperties
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "Action_Script_Properties" -Value $ActionProperties
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "Category" -Value $Category
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "PreviousStatus" -Value $PreviousStatus
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "DataDir" -Value $DataDir
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "StatusFile" -Value $StatusFile
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "MaintenanceMode" -Value $MaintenanceMode
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "AlwaysInvokeAction" -Value $AlwaysInvokeAction
     
        # Add Thing to arraylist
        $ThingsToMonitor.Add($ThingToMonitor)|Out-Null
    }
}

$ThingsToMonitor