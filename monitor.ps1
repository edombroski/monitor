<#
    .SYNOPSIS
        Monitor things using pluggable scripts.

    .DESCRIPTION
        Monitor.ps1 is an agent-less, dependency-less, flexible and pluggable PowerShell monitoring script infrastructure.

        It consists of:
            1. One or more test scripts (.ps1 files)
            2. One or more (optional) action scripts (.ps1 files)
            3. This wrapper script that calls the test scripts, passing the configured montiors, and invokes the action scripts on status changes.
            4. One or more Comma-Separated-Value (.csv) configuration files containing things to monitor
            5. XML Status files to keep track of status
            6. (Optional) static HTML status dashboards
            5. Helper scripts to automatically discover things to monitor and manage configuration .csv files

        Pseudocode:
            For Each thing_to_monitor
                Previous_Status=( get_status_from_status_file )
                Current_Status =( run_test_script )
                If( Current_Status != Previous_Status ) 
                    run_action_script

        For efficiency, the monitored objects are grouped by test (and possibly further) and passed to the test script on the pipeline.

        Optionally, this may be run in "MP" (multi-processing) mode, in which those tests are done via PowerShell background jobs.

    .PARAMETER TestScriptsToRun
        Only run test scripts in given list (excluding .ps1 extension).

    .PARAMETER TestCategoriesToRun
        Only run tests defined in a specific category.  

        The category is the CSV file name with underscores converted to spaces without the .csv extension.

    .PARAMETER Targets
        Only run tests against specific targets.

    .PARAMETER OnlyDown
        Only run tests against systems previously marked not OK

    .PARAMETER OnlyUp
        Only run tests against systems previously marked OK

    .PARAMETER MPMode
        Utilize multiple background jobs for the tests.

        Currently, this script groups tests by the attribute defined by GroupBy and 
        invokes a single background job per group.
    
        This mode is particularly useful if you have several 'slow' test types or many thousands of nodes
        that can be split up into multiple input files.

        A future enhancement is expected to add batching within a group.

    .PARAMETER GroupBy
        If using MP mode, which attribute we used to group monitors into

        Currently supported:
            "Category+Test":    use one (or more) background jobs per Category+Test
            "Test_Script":      use one (or more) background jobs per Test script.)

    .PARAMETER MaxJobs
        Maximum total background jobs to run concurrently

    .PARAMETER WaitMs
        Milliseconds to wait between jobs

#>
[CmdletBinding()]
Param
(
    [ValidateScript({ $_ -in ((Get-ChildItem "$($psscriptroot)\test_scripts").Name.Replace(".ps1",""))})]
    [string[]]
    $TestScriptsToRun,

    [ValidateScript({ $_ -in ((Get-ChildItem "$($psscriptroot)\monitor_configs").Name.Replace("_"," ").Replace(".csv",""))})]
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
    $Quiet, 

    [switch]
    $MPMode, 

    [ValidateSet("Test_Script","Category+Test")]
    [string]
    $GroupBy="Category+Test",

    [int]
    $MaxJobs=$env:NUMBER_OF_PROCESSORS+1,

    [int]
    $WaitMs=500
)

# Get start time for end statistics
$StartTime = Get-Date

# Load script config (for file location, etc.)
. "$($psscriptroot)\config.ps1"

# Load functions
. "$($psscriptroot)\functions.ps1"

Write-LogHost "Starting monitor."

If($OnlyUp -and $OnlyDown) {
    Write-ErrorMessage "OnlyUp and OnlyDown cannot be provided at the same time, exiting."
    Return
}
If($OnlyUp) {
    Write-LogHost "OnlyUp set, only performing tests on nodes with Status=OK"
}
ElseIf($OnlyDown) {
    Write-LogHost "OnlyDown set, only performing tests on nodes with Status!=OK"

}

# Set environment variable for monitor script path
# This is so the script blocks can find the functions
$env:_MonScriptPath=$($PSScriptRoot)

#####################################################################################################
# MP Script Block Wrapper
#####################################################################################################
# To perform the monitor tests, I pipe an array of parameter objects to a ScriptBlock
#
# The standard way of doing multi-processing in PowerShell is using Start-Job
#
# While Start-Job takes a ScriptBlock as a parameter, it doesn't seem to take pipeline input to it.
#
# So, I use this "wrapper" ScriptBlock to do so
#
# I use one array of 'TestParameters' that is fed to it (as a single Array paremter) iva -ArgumentList
#
# The first object in the array is the ScriptBlock I want the wrapper to invoke
#
# The rest of the objects are the parameter objects to that ScriptBlock
#
# I am led to believe I *should* be able provide one parameter a string representing the ScriptBlock,
# and another array parameter (via the (,$ArrayName) syntax) containing the parameter objects
#
# This does seem to work when you do one or the other, but if both are provided it seems to flatten
# the array into one object. So to get around this I use one array.
######################################################################################################
$TestScriptBlockWrapper = {
    Param([object[]]$TestParameters)

    # Get number of objects so we can determine size of parameter objects array
    $NumberOfObjects = ($TestParameters|Measure).Count

    # First parameter is the script block we want to run
    Try {
        $ScriptBlock = [scriptblock]::Create($TestParameters[0])
    }
    Catch {
        Write-ErrorMessage "Failed to create script block from file"
        Return
    }

    # Rest of the parameters are the objects to pipe to it
    Try {
        $TestParameterObjects= $TestParameters[1..$($NumberOfObjects -1)]
    }
    Catch {
        Write-ErrorMessage "Can't get parameter objects."
        Return
    }

    $TestParameterObjects|&$ScriptBlock
}


# Get contents of all the test scripts into a hashtable by test
$Tests=@{}
$TestScriptFiles = Get-ChildItem $TestScriptLocation
Foreach($TestScript in $TestScriptFiles) {
    $TestName = $TestScript.Name.Replace(".ps1","")
    $TestContents = Get-Command $TestScript.FullName | Select -ExpandProperty ScriptBlock
    $Tests.Add($TestName,$TestContents)
}


# Get contents of all the action scripts into a hashtable by action
$Actions=@{}
$ActionScriptFiles = Get-ChildItem $ActionScriptLocation
Foreach($ActionScript in $ActionScriptFiles) {
    $ActionName = $ActionScript.Name.Replace(".ps1","")
    $ActionContents = Get-Command $ActionScript.FullName | Select -ExpandProperty ScriptBlock
    $Actions.Add($ActionName,$ActionContents)
}


# Get monitor configuration .csv files
$MonitorConfigFiles = Get-ChildItem $MonitorConfigFilesLocation

# Create arraylist for .csv configurations
$ThingsToMonitor = New-Object System.Collections.ArrayList

# Create arraylist to hold results
$Results         = New-Object System.Collections.ArrayList

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
            Write-LogHost "Creating status file $StatusFile"
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

        # Build a Category+Test value so we can group by that combination for later MP purposes
        $CategoryTest=($Category+"|"+$ThingToMonitor.Test_Script).Replace(" ","").ToLower()


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
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "Category+Test" -Value $CategoryTest
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "PreviousStatus" -Value $PreviousStatus
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "DataDir" -Value $DataDir
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "StatusFile" -Value $StatusFile
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "MaintenanceMode" -Value $MaintenanceMode
        Add-Member -InputObject $ThingToMonitor -MemberType "NoteProperty" -Name "AlwaysInvokeAction" -Value $AlwaysInvokeAction
     
        # Add Thing to arraylist
        $ThingsToMonitor.Add($ThingToMonitor)|Out-Null
    }
}




###############################################################################################################################
# RUN TESTS
###############################################################################################################################
# The primary idea of this script is to have standalone .ps1 scripts that can perform a test and produce a result all by itself
# For each thing to monitor, I *could* call the .ps1 script with the given parameters, but that seems inefficient
# Instead, I use Group-Object to group all the things to monitor by test (or, even further, by category)
# Then I can pipe all the 'things to monitor' configurations for a given test into that script
# Thus the BEGIN section of the the particular .ps1 is only invoked once for that test or test/category combination
###############################################################################################################################

# Group things by given parameter
$ThingsToMonitorGroup = $ThingsToMonitor|Group-Object $GroupBy

# Get the Tests time for end statistics
$TestStartTime=Get-Date

# If Multi-Processing Mode, create jobs queue
If($MPMode) {
    $Jobs=@()
    Write-LogHost "MP Mode: Group by attribute: $GroupBy"
}

# Go through each group 
Foreach($ThingToMonitorGroup in $ThingsToMonitorGroup ) {

    # Get test name from group name
    If($GroupBy -eq "Test_Script") {
        $Test = $ThingToMonitorGroup.Name
    }
    ElseIf($GroupBy -eq "Category+Test") {
        $Category, $Test = $ThingToMonitorGroup.Name.Split("|")
    }

    # Get test script path from hash
    If($Tests[$Test]) {
        $TestScriptBlock  = $Tests[$Test]
    }
    Else {
        Write-Warning "No test script for test ""$($Test)"""
        Continue
    }

    # Build property objects to pipe to test scripts
    $TestPropertyObjects = New-Object System.Collections.ArrayList
    Foreach($ThingToMonitor in $ThingToMonitorGroup.Group) {
        $ThingToMonitor.Test_Script_Properties.Add("MonitorObject",$ThingToMonitor)
        $TestPropertyObjects.Add([pscustomobject]$ThingToMonitor.Test_Script_Properties)|Out-Null
    }

    # If we're doing MP mode, insert the scriptblock to the property objects
    # Results will be grabbed by Get-Job later
    If($MPMode) {
        $TestPropertyObjects.Insert(0, $TestScriptBlock)|Out-Null

        # Wait for max jobs to execute before starting another one
        While( (Get-Job|?{$_.State -eq "Running"}|Measure).Count -ge $MaxJobs ) {
            Write-LogHost "MP Mode: Max concurrent jobs exceeded...waiting."
            Start-Sleep -Milliseconds $WaitMs
        }

        # Invoke Background Job
        Try {
            Write-LogHost "MP Mode: Starting job for test $($Test)."
            $Jobs+=$(Start-Job -ScriptBlock $TestScriptBlockWrapper -ArgumentList (,$TestPropertyObjects))
            Write-LogHost "MP Mode: Done."
        }
        Catch {
            Write-LogHost "MP Mode: Failed."
            Write-ErrorMessage "MP Mode: Error creating job"
        }

    }

    # Single Process/serial mode.  Just pass property objects to the script block
    # Add results to array
    Else {
        # Get test results from script block
        $TestResults = $TestPropertyObjects | &$TestScriptBlock

        If($TestResults) {
            If(($TestResults|Measure).Count -eq 1) {
                $Results.Add($TestResults)|Out-Null
            }
            Else {
                $Results.AddRange($TestResults)|Out-Null
            }
        }
    }

}

# If MP mode, get results from Get-Job and cleanup
If($MPMode) {
        
    # Get results
    If($Jobs) {
        # Get all results
        Write-LogHost "MP Mode: Waiting for jobs to complete."
        $Results = $Jobs|Get-Job|Wait-Job|Receive-Job
        Write-LogHost "MP Mode: Done"

        # Clean up jobs
        Write-LogHost "MP Mode: Cleaning up jobs."
        $Jobs|Remove-Job
        Write-LogHost "MP Mode: Done."
    }
   
}

# End time for test stats
$TestEndTime=Get-Date

# Results count for stats
$ResultsCount = ($Results|Measure).Count

###############################################################################################################################
# PROCESS RESULTS
###############################################################################################################################
Foreach($Result in $Results) {
    $CurrentStatus  = $Result.CurrentStatus
    $PreviousStatus = $Result.PreviousStatus
    $AlwaysInvokeAction = $Result.AlwaysInvokeAction
    $RunActionScript = $False

    ##################################################################
    #  NOTICE: One time alert, run action but set status=OK
    ##################################################################
    If($CurrentStatus -eq "NOTICE") {
        Write-LogHost -StatusChange "NOTICE:`tMonitor=$($Result.Monitor_Name), Target=$($Result.Target), Test=$($Result.Test_Script)"
        Write-LogHost -StatusChange "STATUS MESSAGE:`t$($Result.Message)"
        $StatusObject = [pscustomobject]@{
            "Status"="OK"
        }
        $StatusObject | Export-CLIXML $Result.StatusFile
        $RunActionScript=$True        
    }


    ##################################################################
    #  STATUS CHANGE: Store current status
    ##################################################################
    ElseIf($CurrentStatus -ne $PreviousStatus) {

        Write-LogHost -StatusChange "STATUS CHANGE:`tMonitor=$($Result.Monitor_Name), Target=$($Result.Target), Test=$($Result.Test_Script), Change=[$($PreviousStatus) -> $($CurrentStatus)]"
        If($Result.Message) {
            Write-LogHost -StatusChange "STATUS MESSAGE:`t$($Result.Message)"
        }
        $StatusObject = @{
            "Status"=$CurrentStatus
        }

        $StatusObject | Export-CLIXML $Result.StatusFile

        ##################################################################
        #  Previous status was INIT, don't run action
        ##################################################################
        If($PreviousStatus -eq "INIT") { 
            Write-LogHost -StatusChange "ACTION TAKEN:`tNone (Previous state INIT)"
            Continue 
        }

        ##################################################################
        #  Previously in maintenance mode, now OK, don't run action
        ##################################################################
        ElseIf($PreviousStatus -eq "MAINT" -and $CurrentStatus -eq "OK") { 
            Write-LogHost -StatusChange "ACTION TAKEN:`tNone (Previous Status=MAINT, Current Status=OK)"
            Continue 
        }


        ##################################################################
        #  Previously OK or now OK, run action
        ##################################################################
        ElseIf($CurrentStatus -eq "OK" -or $PreviousStatus -eq "OK") {
            $RunActionScript=$True
        }
    }


    ##################################################################
    #  Not OK but AlwaysInvokeAction is set, run action
    ##################################################################
    ElseIf($CurrentStatus -ne "OK" -and $AlwaysInvokeAction) {
        Write-LogHost -StatusChange "STATUS UPDATE:`tMonitor=$($Result.Monitor_Name), Target=$($Result.Target), Test=$($Result.Test_Script)"
        Write-LogHost -StatusChange "STATUS MESSAGE:`t$($Result.Message)"
        If($Result.Action_Script) {
            Write-LogHost -StatusChange "ACTION TAKEN:`t$($Result.Action_Script) (Previous Status=$($PreviousStatus), Current Status=$($CurrentStatus), ALWAYS_INVOKE_ACTION=True)"
        }
        Else {
            Write-LogHost -StatusChange "ACTION TAKEN:`tNone (ALWAYS_INVOKE_ACTION=True but no Action_Script defined)"
        }
    }


    ###############################################################################################################################
    # RUN ACTIONS
    ###############################################################################################################################
    If($RunActionScript) {
        If($Result.Action_Script) {
            If($Actions[$Result.Action_Script]) {
                Write-LogHost -StatusChange "ACTION TAKEN:`t$($Result.Action_Script)"
            }
            Else {
                Write-LogHost -StatusChange "ACTION TAKEN:`tNone (No Action_Script of $($Result.Action_Script) exists)"
            }
        }
        Else {
            Write-LogHost -StatusChange "ACTION TAKEN:`tNone (No Action_Script defined)"
        }
    } 
}

# Write last run file
(Get-Date).ToString()|Out-File -Encoding ASCII $LastRunFile

$EndTime = Get-Date
$TestSeconds = ($TestEndTime - $TestStartTime).TotalSeconds
$TotalSeconds = ($EndTime - $StartTime).TotalSeconds
Write-LogHost "Performed $ResultsCount tests."
Write-LogHost "Tests execution time: $($TestSeconds) seconds"
Write-LogHost "Total execution time: $($TotalSeconds) seconds"

Write-LogHost "Ending monitor."
