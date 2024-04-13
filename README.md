# Monitor.ps1

Monitor.ps1 is an agent-less, pluggable PowerShell monitoring script.

The infrastructure can be configured to monitor anything that PowerShell script (.ps1) can be written for that produces an "OK" or "NOT OK" results.

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

2. No dependencies. This does not require any database or web application.  All status information is kept on the filesystem in easily human and machine readable XML files.  No third-party modules are required for the base infrastructure, nor does it require a database, web application, or any other components other than PowerShell Core (7+). 

3. Supports "multi-process" mode which splits up monitoring jobs into multiple PowerShell background jobs. In normal single-process mode using the "ping" test, ~3300 'up' nodes with average latency of about ~13ms can be pinged in about 45 seconds. In multi-process mode, the same 3300 nodes can be pinged in about 18 seconds.  MP mode is likely make a much larger difference improving the overall throughput of slower tests against remote systems (disk space checks, etc.)
4. Maintenance Mode. Specific monitors can be temporarily disabled.
5. Repeated Actions. An action script can be repeated on a configurable interval.
6. "NOTICE" alerts for one-time events.
7. Optional static HTML dashboards of status information.

## WHAT THIS ISNT
A replacement for a grown-up agent-based monitoring system such as Zabbix, SCOM, etc. or a more fully featured SNMP based system like SolarWinds. This script does not poll any sort of time-series information like performance data, error counts, etc.

## PSEUDOCODE
        For Each thing_to_monitor
            Previous_Status=( get_status_from_status_file )
            Current_Status =( run_test_script )
            If( Current_Status != Previous_Status ) 
                run_action_script

## v2 CHANGES
1. Written for PowerShell core instead of Windows PowerShell
2. Use folders for test data instead of just files (possible future usecases)
3. Use XML files and Import-CLIXML/Export-CLIXML instead of plaintext status files (possible future usecases)
4. Pass full monitor configuration objects to test scripts
5. Combine .CSV options into one column and rename columns
6. Initial multi-process mode
7. New parameters (TestCategoriesToRun, OnlyUp, OnlyDown, Quiet)
8. New options (Always_Invoke_Action)

## v2 TODO
1. Add back action scripts
2. Add back status dashboards
3. Re-write test scripts for new infrastructure
4. Add function to clean up monitor data for monitor configs that don't exist
5. Add function to place a target into maintenance mode in all configs
6. Re-write helper scripts for new configuration syntax

## v.NEXT IDEAS
1. Convert background jobs to use PowerShell runspaces
2. Splitting up of tests in one config file+test combination
2. MP-safe Log+Host function that tests can use
3. Keep track of lastChange, lastNotOK, notOKCount in status files
4. "Intermediate" status value between OK and !OK (e.g. "Monitoring" )
5. Per test configurable intervals
6. Automatic maintenance mode timeouts
7. Credential management



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

## EXAMPLE TEST SCRIPTS TO BE INCLUDED

### ping
Test host availability via ICMP echo (ping).

### http
Tests remote web server availability via Invoke-WebRequest. Supports various options such as searching for a specific JSON key/value.

### ports
Tests a remote system for if a configured set of TCP or UDP ports are open.

### sslcert
Tests a remote system's SSL/TLS certificate for nearing expiration.

### service
Tests a remote (Windows) system if a service is running. Utilizes Remote PowerShell.

### task
Tests a remote (Windows) system if a Windows scheduled task is enabled and has run successfully within a configurable timeframe. Utilizes Remote PowerShell.

### disk
Tests a remote (Windows) system for consumed disk space. Utilizes Remote PowerShell.

### group
Tests a remote (Windows) system for local group membership.  If it changes from a stored value, raise an alert. Utilizes Remote PowerShell.

### smtp
Test successfully relaying an SMTP message through an SMTP server with configurable parameters

### mx
Test successfully transmitting an email via SMTP through the mail-exchanger servers of a specific domain.

### module_import
Test whether a PowerShell module in a given path is loadable.

## account_expirations
Test whether a specific Active Directory account is nearing its expiration date (requires Active Directory PowerShell module).


## EXAMPLE ACTION SCRIPTS TO BE INCLUDED

### email
Sends an email notification to configurable addresses.

## EXAMPLE HELPER SCRIPTS TO BE INCLUDED

### Update-WindowsHostMonitors.ps1
Queries a set of Active Directory OUs for computer account objects, and automatically adds/removes monitoring objects accordingly. Requires Active Directory module.

### Update-SolarWindsNodeMonitors.ps1
Queries the database of a SolarWinds Network Performance Monitor system for a list of nodes to ping.

### Update-MistAPMonitors.ps1
Queries the the MIST networks API for a list of sites and Access Points and their IP addresses. Requires Mist API access.