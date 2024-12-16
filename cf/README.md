# Cloudflare Auto Update Script

This script is designed to automate the process of whitelisting and managing IP addresses for QUIC.cloud services on Cloudflare. It allows you to easily add or remove IP addresses based on the latest data from QUIC.cloud, ensuring your firewall rules are up to date.

## Features

- Automatically fetches the latest QUIC.cloud IP addresses.
- Whitelists new IP addresses in your Cloudflare account.
- Deletes QUIC.cloud IP addresses on your request.
- Progress indicators for both whitelisting and deletion processes.
- Simple to set up and run with cron jobs.

## Requirements

- A Cloudflare account with an API key.
- `curl` for making HTTP requests.
- `jq` for parsing JSON responses. (The script checks for `jq` and can guide users to install it if missing.)

## Installation

1. Download the script:
   ```bash
   wget -q https://raw.githubusercontent.com/QuicCloud/scripts/main/cf/cloudflare-auto-update.sh -P /opt/
2. Make the script executable:
   ```bash
   chmod +x /opt/cloudflare-auto-update.sh
3. Set up your Cloudflare credentials in the script: Edit the script and provide your Cloudflare email, API key, and zone ID:
   ```bash
   CF_EMAIL="your_email@example.com"
   CF_API_KEY="your_api_key"
   CF_ZONE_ID="your_zone_id"
To find those credentials:
* CF_EMAIL: simply your email for your account. Can be found on the top left corner of the Cloudflare website;
* CF_API_KEY: Go to your profile (top right corner icon) -> My Profile -> API Tokens -> Global API Key => View ;
* CF_ZONE_ID: Go to your home dashboard -> click on your website domain -> the Zone ID is at the bottom right side of the screen (see [this tutorial](https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/)).

## Usage

You can run the script manually or set it up as a cron job for automated execution.

1. **Manual Execution**
   - To whitelist IPs:
     ```bash
     /opt/cloudflare-auto-update.sh
   - To delete QUIC.cloud IPs:
     ```bash
     /opt/cloudflare-auto-update.sh delete
2. **Cron Job Setup** \
    To run the script daily at midnight, add the following line to your crontab:
    ```bash
    0 0 * * * /opt/cloudflare-auto-update.sh
