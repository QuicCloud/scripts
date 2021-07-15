# csf-auto-update
This script is design for the auto whitelisting Quic Cloud IPs for ConfigServer Security & Firewall.

## Options
|  Opt  |    Options    | Description|
| :---: | ---------  | ---  |
| `-U` |`--update`|   Add/Update quic.cloud/ips to both csf.allow and csf.ignore list|
| `-R` |`--restor`|   Restore csf.allow and csf.ignore to origin|
| `-H` |`--help`  |   To display help messages|

## Usage
1. Download and give permission to the script
    ```
    wget -q https://raw.githubusercontent.com/QuicCloud/scripts/main/csf/csf-auto-update.sh -P /opt/
    ```
    ```
    chmod +x /opt/csf-auto-update.sh
    ```

2. Add following example rule to the cronjob \
Edit cronjob with `crontab -e` command, and insert following rule which will run every day at 00:00

    ```
    0 0 * * * /opt/csf-auto-update.sh
    ```
