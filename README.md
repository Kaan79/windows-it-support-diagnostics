# Windows IT Support Diagnostics Toolkit

A PowerShell-based Windows troubleshooting and information-gathering tool created as an IT Support portfolio project.

## Features

1. **System information** — computer name, current user, Windows edition/version/build, last boot time, and uptime.
2. **Network information** — active network adapters, IPv4 addresses, default gateways, and DNS server addresses.
3. **Connectivity diagnostics** — gateway ping, public IP ping, DNS name resolution, and a TCP connection test to port 443.
4. **Windows services** — read-only status checks for BITS, Print Spooler, Windows Update, DHCP Client, and Windows Audio.
5. **Event Viewer diagnostics** — queries the System log for Service Control Manager errors and warnings from the last 24 hours (up to 20 events).
6. **Automatic report generation** — saves a timestamped text report in the reports directory.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or later
- Built-in Windows networking and event-log cmdlets
- No third-party PowerShell modules required

## Run

Open PowerShell in the project directory and execute:

    .\src\diagnostics.ps1

If script execution is restricted, allow this script for the current PowerShell process only:

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\src\diagnostics.ps1

## Output

A report is created under reports/ with a timestamped name, for example:

    reports/Diagnostics_YYYYMMDD_HHMMSS.txt

## Privacy and safety

The script performs read-only diagnostics. It does not start, stop, enable, disable, or reconfigure Windows services or network settings.

Generated reports may contain the computer name, Windows username, local IP addresses, and event messages. Generated reports are excluded from Git by .gitignore. Review a report and remove sensitive information before sharing it manually.

## Notes and limitations

- A failed ping does not always mean a host is offline; ICMP may be blocked by a firewall or network policy.
- The TCP port 443 test checks whether a TCP connection can be established to the selected IP. It does not validate a website TLS certificate or full HTTP response.
- DNS testing uses google.com as a sample domain.
- Event log collection is limited to the System log, the Service Control Manager provider, Error/Warning levels, the last 24 hours, and at most 20 events.
- Some event logs or system details may require elevated permissions in managed environments.

## Project structure

    Windows-IT-Support-Diagnostics/
    ├── src/
    │   └── diagnostics.ps1
    ├── reports/
    │   └── .gitkeep
    ├── .gitignore
    └── README.md

## Skills demonstrated

PowerShell scripting, Windows services, CIM/WMI queries, IP configuration, ICMP connectivity checks, DNS resolution, TCP port diagnostics, Windows Event Logs, error handling, and text report generation.