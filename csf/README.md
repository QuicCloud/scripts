# csf-auto-update
This script is designed to facilitate automatic allowlisting of QUIC.cloud IPs in ConfigServer Security & Firewall (CSF).

## Options
|  Opt  |    Options    | Description|
| :---: | ---------  | ---  |
| `-U` |`--update`|   Add/Update quic.cloud/ips to both csf.allow and csf.ignore list|
| `-R` |`--restore`|   Restore csf.allow and csf.ignore to origin|
| `-H` |`--help`  |   Display help messages|

## Usage
1. Download and give permission to the script
    ```
    wget -q https://raw.githubusercontent.com/QuicCloud/scripts/main/csf/csf-auto-update.sh -P /opt/
    ```
    ```
    chmod +x /opt/csf-auto-update.sh
    ```

2. Add a rule to the cronjob \
Edit cronjob with the `crontab -e` command, and insert a rule similar to the following. This example will run every day at 00:00:

    ```
    0 0 * * * /opt/csf-auto-update.sh -u
    ```
