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
    $OnlyUp

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
    }
}