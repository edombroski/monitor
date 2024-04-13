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

## TEST SCRIPTS

## ACTION SCRIPTS

## CSV FORMAT

## EXAMPLE TEST SCRIPTS INCLUDED

### ping

### http