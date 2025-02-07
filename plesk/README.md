# QUIC.cloud IPs Fail2Ban Trusted List Manager

This script automates the process of adding and removing QUIC.cloud IPs to/from the Plesk Fail2Ban Trusted (Allow) List. By doing so, it ensures that QUIC.cloud IPs are never blocked by Fail2Ban, improving reliability for LiteSpeed services.

## Features

- Fetches the latest QUIC.cloud IPs automatically
- Adds IPs to the Fail2Ban Trusted List in Plesk
- Removes IPs from the Trusted List if needed
- Prevents duplicate entries
- Logs added and removed IPs for tracking

## Requirements

- Plesk server with Fail2Ban enabled
- `curl` and `jq` installed

## Installation

1. Download the script using the following command:
   ```bash
   wget https://raw.githubusercontent.com/QuicCloud/scripts/main/plesk/plesk_fail2ban.sh
2. Make the script executable:
   ```bash
   chmod +x plesk_fail2ban.sh

## Usage

You can run the script manually or set it up as a cron job for automated execution.

1. **Manual Execution**
   - Add QUIC.cloud IPs to Trusted List:
     ```bash
     ./plesk_fail2ban.sh -add
   - Remove QUIC.cloud IPs from Trusted List
     ```bash
     ./plesk_fail2ban.sh -delete
2. **Cron Job Setup** \
    To run the script daily at midnight, add the following line to your crontab:
    ```bash
    0 0 * * * plesk_fail2ban.sh -add
