# Monitor.ps1

Monitor.ps1 is an agent-less, pluggable PowerShell monitoring script.

The infrastructure can be configured to monitor anything that PowerShell script (.ps1) can be written for that produces an "OK" or "!OK" result.

The base script designed to require no dependencies other than PowerShell core.



It consists of:
1. One or more test scripts (.ps1 files)
2. One or more (optional) action scripts (.ps1 files)
3. This wrapper script that calls the test scripts, passing the configured montiors, and invokes the action scripts on status changes.
4. One or more Comma-Separated-Value (.csv) configuration files containing things to monitor
5. XML Status files to keep track of status
6. (Optional) static HTML status dashboards
7. Helper scripts to automatically discover things to monitor and manage configuration .csv files

(Not all of these components are available on Github yet)


        Pseudocode:
            For Each thing_to_monitor
                Previous_Status=( get_status_from_status_file )
                Current_Status =( run_test_script )
                If( Current_Status != Previous_Status ) 
                    run_action_script



## TEST SCRIPTS

Each test script is designed to be able to be invoked as a standalone script, or called via this Monitor.ps1 wrapper.

If called from the wrapper script, a custom object (MonitorObject) will also be passed.

It is expected the test script modify the ModifyObject "status" property and return it.

It may also modify the "message" property to provide a more verbose message.

If the test "passes", the status must be set to the string "OK"

If the test is designed to only produce a one-time alert, the status must be set to "NOTICE"

Any other status is considered by the wrapper script to be a failure condition (aka DOWN, PROBLEM, etc.) and react accordingly.


## ACTION SCRIPTS

An (optional) action script can be invoked on a status change, most often between "OK" and "!OK" statuses.

It is expected that this action script will only be invoked once.

This can be overridden using the ALWAYS_INVOKE_ACTION per test option.

Currently, only one action script may be invoked per monitor.

## CSV FORMAT

Monitor_Name, Target, Test_Script, Test_Script_Params, Action_Script, Action_Script_Params, Options

    Monitor_name:   Required text string that identifies a monitor "display name" of sorts.
    Target:         Target of the test.  Typically a hostname or IP address. May (or may not) match the Monitor_Name.
    Test_Script:    .ps1 test script to invoke (without the .ps1).  Should produce "OK" status if test passes, and something else if test fails.
    Test_Params:    key=value parameters to pass to test script, comma separated. Multi-valued values may be semi-colon separated.
    Action_Script:  Optional .ps1 action script to invoke on state change
    Action_Params:  key=value parameters to pass to monitor script, ??? separated
    Options:        key=value options specific to this monitor but not passed to test script
                    Currently supported options:
                        MAINTENANCE_MODE
                            Place monitor in "maintenance" mode. Test will not be run, status will be updated to MAINT

                        ALWAYS_INVOKE_ACTION=(OK,NOTOK,ALWAYS)
                            Always invoke the action script if the result is !OK

                        REPEAT_ACTION_MINUTES
                            Number of hours before repeating the action. Useful for "nagging".
                            
                            LastWriteTime of internal status indicator file is checked against current time, action script is invoked

                            Set to 0 to not repeat the action.

                            Default=720 (every 12 hours)

## EXAMPLE TEST SCRIPTS INCLUDED

### ping

### http