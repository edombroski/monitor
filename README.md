# Monitor.ps1

Monitor.ps1 is an agent-less, pluggable PowerShell monitoring script.

The infrastructure can be configured to monitor anything that PowerShell script (.ps1) can be written for that produces an "OK" or "!OK" result.

The base script designed to require no dependencies other than PowerShell core.

It consists of:
1. One or more test scripts (.ps1 files) that can be fed a list of things to monitor via the pipeline.
2. One or more (optional) action scripts (.ps1 files) that can be invoked.
3. The Monitor.ps1 wrapper script that calls the test scripts (passing the things to monitor), and optionally invokes the action scripts on status changes.
4. One or more Comma-Separated-Value (.csv) configuration files containing things to monitor
5. XML status files to keep track of status
6. (Optional) static HTML status dashboards
7. Helper scripts to automatically discover things to monitor and manage configuration .csv files

This version is currently in beta as I am undertaking a re-write.  Not all of the above is available on GitHub yet.


## FEATURES

1. Flexibility. This script can monitor a number of different things (ping availability, website availability, ports being open, disk space, group memberships, etc.). Anything that you can write a PowerShell script for to produce a "OK" or "NOT OK" result can be monitored.
2. No dependencies. This does not require any database or web application.  All status information is kept on the filesystem in easily human and machine readable XML files.  No third-party modules are required outside for the base infrastructure other than PowerShell core (some tests, actions, or helper scripts may require other modules).
3. Supports "multi-process" mode which splits up monitoring jobs into multiple PowerShell background jobs. In normal single-process mode using the "ping" test, ~3300 'up' nodes with average latency of about ~13ms can be pinged in about 45 seconds. In multi-process mode, the same 3300 nodes can be pinged in about 18 seconds.  MP mode is likely make a much larger difference improving the overall throughput of slower tests against remote systems (disk space checks, etc.)
4. Maintenance Mode. Specific monitors can be temporarily disabled.
5. Repeated Actions. An action script can be repeated on a configurable interval.
6. "NOTICE" alerts for one-time events.
7. Optional static HTML dashboards of status information.

## WHAT THIS ISNT
... replacement for a grownup agent based monitoring system such as Zabbix.

## PSEUDOCODE
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

### ports

### service

### task

### disk


## EXAMPLE ACTION SCRIPTS INCLUDED

### email

## HELPER SCRIPTS

### email