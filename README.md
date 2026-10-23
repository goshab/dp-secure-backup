The postings on this site are my own and don't necessarily represent IBM's positions, strategies or opinions.

# DataPower Secure Backup automation

This script automates the DataPower Secure Backup process across one or more DataPower gateways.

## Features

- Supports one or more DataPower gateways, all defined in a single configuration file.
- Optionally switches Gateway Peering primary to a peer gateway and quiesces the domain before taking the backup, then un-quiesces it afterwards.
- Creates a Secure Backup on each DataPower gateway.
- Downloads the backup files to the local filesystem.
- Optionally pushes the backup files to a git repository.

## Overview

- The XML Management Interface (SOMA) and the AMP management interface are used to access the DataPower gateway.
- Gateways are processed one at a time, in the order listed in `DP_SERVERS`.
- When quiescing is enabled, Gateway Peering primary is switched to the *next* gateway in `DP_SERVERS` (wrapping around to the first) before the current gateway's domain is quiesced, so this flow is intended for gateways set up in a peering/failover group.
- Secure Backup and file download happen regardless of whether quiescing is enabled.
- The local folder for each gateway's backup consists of the backups root folder, the DataPower hostname/IP, the firmware version, and the Secure Backup's timestamped folder name.

## Prerequisites

- `curl`
- `xmlstarlet`
- `jq`

## Support

Successfully tested setup:

- DataPower 10.0.5.2.

## Configuration overview

### Per-project configuration (one file per automation run)

| Parameter                | Description                                                                                                                                                                            | Example                                              |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| DP_SERVERS               | JSON array of the DataPower gateways to process. Each entry needs `mgmt_ip`, `soma_port`, `user_name`, `user_password`, and `sb_certificate` (the Crypto Certificate preconfigured in the default domain, used to encrypt the backup). | See [00-project-template.conf](00-project-template.conf) |
| DO_QUIESCE               | Whether to switch Gateway Peering primary and quiesce/un-quiesce the domain around the backup. Set to `false` to just take the backup with no peering/quiesce steps.                     | <code>true</code> \| <code>false</code>              |
| QUIESCE_DOMAIN           | The application domain to quiesce. Only used when `DO_QUIESCE=true`.                                                                                                                      | <code>apiconnect</code>                               |
| QUIESCE_TIMEOUT          | Timeout, in seconds, passed to the appliance for the quiesce operation itself (how long it waits before terminating in-flight transactions).                                              | <code>120</code>                                     |
| QUIESCE_STATUS_POLL_INTERVAL | Seconds to wait between the script's own checks of whether the domain has finished quiescing.                                                                                         | <code>10</code>                                      |
| QUIESCE_STATUS_POLL_MAX_CHECKS | Maximum number of status checks before the script gives up waiting for the domain to quiesce and aborts.                                                                            | <code>30</code>|
| INCLUDE_ISCSI            | Whether to back up the ISCSI device.                                                                                                                                                      | <code>on</code> \| <code>off</code>                  |
| INCLUDE_RAID             | Whether to back up the RAID device.                                                                                                                                                       | <code>on</code> \| <code>off</code>                  |
| DESTINATION              | A directory on the gateway to place the multiple files that comprise the backup.                                                                                                          | <code>temporary:///</code> \| <code>local:///</code> |
| ADD_TO_GIT               | Whether to push the downloaded backup files to a git repository.                                                                                                                           | <code>true</code> \| <code>false</code>              |
| GIT_REMOTE_NAME          | Git repository remote name.                                                                                                                                                               | <code>origin</code>                                  |
| GIT_BRANCH_NAME          | Git branch name.                                                                                                                                                                           | <code>main</code>                                    |
| EMPTY_LOG_FILE_ON_START  | Whether to clear the log file at the start of each run.                                                                                                                                    | <code>true</code> \| <code>false</code>              |
| DEBUG                    | Whether to additionally log the full SOMA/AMP request and response bodies.                                                                                                                | <code>true</code> \| <code>false</code>              |

### System-level configuration ([system.conf](system.conf), shared across all projects, rarely needs changing)

| Parameter               | Description                                                     | Example       |
| ------------------------ | ----------------------------------------------------------------- | ------------- |
| CURL_CONNECTION_TIMEOUT  | Seconds curl waits to establish a connection to a gateway.        | <code>3</code> |
| FOLDER_LOGS              | Folder where run logs are written.                                | <code>logs</code> |
| FOLDER_BACKUPS           | Folder where downloaded backup files are written.                 | <code>backups</code> |

## Usage

- Duplicate the provided [project configuration template](00-project-template.conf) and fill it out, listing every gateway to back up in `DP_SERVERS`.
- Run the automation script, passing the configuration file as an argument. For example:

  | <code>./01-secure-backup.sh nonprd-lan.conf</code> |
  | ------------------------------------------- |
