[<img src="https://img.shields.io/badge/slack-LiteSpeed-blue.svg?logo=slack">](https://litespeedtech.com/slack) 

# QUIC.cloud Scripts Repository

Welcome to the QUIC.cloud Scripts repository! This repository contains automation scripts designed to help manage QUIC.cloud IPs with popular tools like Cloudflare and ConfigServer Security & Firewall (CSF). These scripts simplify integration and ensure your environment stays up-to-date.

## Scripts

### [Cloudflare Auto Update Script](cf/)
A script to automate the process of managing QUIC.cloud IP addresses with Cloudflare.  
**Features:**
- Whitelists or removes IPs in your Cloudflare account.
- Supports automated execution via cron jobs.

For detailed instructions, refer to the [cf/README.md](cf/README.md) file.

---

### [CSF Auto Update Script](csf/)
A script to streamline the process of adding QUIC.cloud IP addresses to ConfigServer Security & Firewall (CSF).  
**Features:**
- Automatically updates `csf.allow` and `csf.ignore` lists with QUIC.cloud IPs.
- Includes options to restore original lists.

For detailed instructions, refer to the [csf/README.md](csf/README.md) file.

---

### [Plesk Fail2Ban Trusted List Manager](plesk/)
A script to automate the process of managing QUIC.cloud IP addresses with Plesk Fail2Ban Trusted List Manager
**Features:**
- Whitelists or removes IPs in your Plesk Fail2Ban Trusted List Manager.
- Supports automated execution via cron jobs.

For detailed instructions, refer to the [plesk/README.md](plesk/README.md) file.

---

## Contributing
Contributions are welcome! If you have ideas or improvements, feel free to submit a pull request or create an issue.

---
For more information about QUIC.cloud and its services, visit [QUIC.cloud](https://www.quic.cloud/).
