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

    # Go through things to monitor
    Foreach($ThingToMonitor in $CSV) {

        $ThingToMonitor

    }

}