#!/bin/bash

# Define the QUIC.cloud IP source URL
QUIC_CLOUD_IPS_URL="https://quic.cloud/ips?json"

# Check if required tools are installed
for cmd in jq curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it and rerun the script."
        exit 1
    fi
done

# Define the full path to Plesk CLI
PLESK_CLI="/usr/sbin/plesk"

# Verify if Plesk CLI exists
if [ ! -x "$PLESK_CLI" ]; then
    echo "Error: Plesk CLI not found at $PLESK_CLI. Please verify the path."
    exit 1
fi

# Fetch the QUIC.cloud IP list
IP_LIST=$(curl -s "$QUIC_CLOUD_IPS_URL")

# Check if curl succeeded
if [[ -z "$IP_LIST" ]]; then
    echo "Error: Failed to fetch IP list from QUIC.cloud."
    exit 1
fi

# Parse JSON and extract IPs into an array
mapfile -t IPS < <(echo "$IP_LIST" | jq -r '.[]')

# Get the current list of trusted IPs from Plesk
get_trusted_ips() {
    $PLESK_CLI bin ip_ban --trusted | awk '{print $1}'
}

# Function to add IPs to the trusted list
add_ips() {
    local total=${#IPS[@]}
    local added=0
    local skipped=0

    echo "Fetching current trusted IPs..."
    mapfile -t CURRENT_IPS < <(get_trusted_ips)
    echo "Total IPs to add: $total"

    local count=0
    for IP in "${IPS[@]}"; do
        ((count++))
        printf "\rProcessing: %d/%d" "$count" "$total"

        if [[ " ${CURRENT_IPS[@]} " =~ " $IP " ]]; then
            ((skipped++))
        else
            if $PLESK_CLI bin ip_ban --add-trusted "$IP" &>/dev/null; then
                ((added++))
            fi
        fi
    done

    echo -e "\n\nSummary: Added: $added | Skipped: $skipped\n"
}

# Function to remove IPs from the trusted list
remove_ips() {
    local total=${#IPS[@]}
    local removed=0
    local not_found=0

    echo "Fetching current trusted IPs..."
    mapfile -t CURRENT_IPS < <(get_trusted_ips)
    echo "Total IPs to remove: $total"

    local count=0
    for IP in "${IPS[@]}"; do
        ((count++))
        printf "\rProcessing: %d/%d" "$count" "$total"

        if [[ " ${CURRENT_IPS[@]} " =~ " $IP " ]]; then
            if $PLESK_CLI bin ip_ban --remove-trusted "$IP" &>/dev/null; then
                ((removed++))
            fi
        else
            ((not_found++))
        fi
    done

    echo -e "\n\nSummary: Removed: $removed | Not Found: $not_found\n"
}

# Check for script arguments
if [[ "$1" == "-add" ]]; then
    add_ips
elif [[ "$1" == "-delete" ]]; then
    remove_ips
else
    echo "Usage: $0 -add | -delete"
    exit 1
fi
