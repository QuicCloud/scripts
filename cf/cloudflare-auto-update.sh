#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Attempting to install jq..."
  
  # Check for the package manager and install jq accordingly
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum &> /dev/null; then
    sudo yum install -y jq
  else
    echo "Error: Package manager not found. Please install jq manually."
    exit 1
  fi
fi

# Define your Cloudflare credentials
CF_EMAIL="your_cloudflare_email"
CF_API_KEY="your_cloudflare_api_key"
CF_ZONE_ID="your_cloudflare_zone_id"

# URL to fetch QUIC.cloud IPs
QUIC_CLOUD_IPS_URL="https://quic.cloud/ips?json"

# Check if the URL is accessible
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$QUIC_CLOUD_IPS_URL")

if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "Error: Unable to access QUIC.cloud IPs. The URL $QUIC_CLOUD_IPS_URL is down or unavailable (HTTP status: $HTTP_STATUS)."
  exit 1
fi

# Validate Cloudflare credentials
validate_credentials() {
  if [ -z "$CF_EMAIL" ] || [ -z "$CF_API_KEY" ] || [ -z "$CF_ZONE_ID" ]; then
    echo -e "Authentication error: One or more credential inputs are empty. Please check your input details and try again.\n"
    exit 1
  fi

  # Test the credentials by making a simple API request
  AUTH_TEST_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID" \
    -H "X-Auth-Email: $CF_EMAIL" \
    -H "X-Auth-Key: $CF_API_KEY" \
    -H "Content-Type: application/json")

  # Check if the response indicates an authentication error
  if echo "$AUTH_TEST_RESPONSE" | jq -e '.success == false' > /dev/null; then
    echo -e "Authentication error: Invalid Cloudflare credentials. Please check your input details and try again.\n"
    exit 1
  fi
}

# Call the validation function
validate_credentials

# Get QUIC.cloud IPs
QUIC_CLOUD_IPS=$(curl -s "$QUIC_CLOUD_IPS_URL")

# Function to get all whitelisted IPs (with pagination support)
get_whitelisted_ips() {
  local page=1
  local all_ips=()
  
  while true; do
    # Fetch the whitelisted IPs from Cloudflare, with pagination support
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules?page=$page&per_page=50" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json")

    # Parse the IPs from the response
    ips=$(echo "$response" | jq -r '.result[] | select(.mode == "whitelist") | .configuration.value')

    # Add the IPs to the all_ips array
    all_ips+=($ips)

    # Check if we have more pages to fetch
    total_pages=$(echo "$response" | jq -r '.result_info.total_pages')
    if [ "$page" -ge "$total_pages" ]; then
      break
    fi
    ((page++))
  done

  # Return all whitelisted IPs
  echo "${all_ips[@]}"
}

# Function to display progress bar
show_progress() {
  local progress_percent=$((progress * 100 / totalIPs))
  local bar_length=50
  local filled_bar=$((progress * bar_length / totalIPs))
  local empty_bar=$((bar_length - filled_bar))

  printf "\rProgress: ["
  printf "%0.s#" $(seq 1 $filled_bar)
  printf "%0.s " $(seq 1 $empty_bar)
  printf "] %d%% (%d/%d)" "$progress_percent" "$progress" "$totalIPs"
}

# Function to print message in a box
print_box() {
  local message="$1"
  # Find the maximum length of the message lines
  max_length=$(echo "$message" | awk '{ if (length > L) L = length } END { print L }')
  
  # Print top border
  echo -e "\n+$(printf "%0.s-" $(seq 1 $((max_length + 2))))+"

  # Print each line with side borders
  while IFS= read -r line; do
    printf "| %-*s |\n" "$max_length" "$line"
  done <<< "$message"

  # Print bottom border
  echo -e "+$(printf "%0.s-" $(seq 1 $((max_length + 2))))+\n"
}

# Check if the deletion action is specified
if [[ "$1" == "delete" ]]; then
  echo "Deleting QUIC.cloud IPs, please wait..."
  
  # Fetch all whitelisted IPs with pagination
  EXISTING_WHITELISTED_IPS=$(get_whitelisted_ips)

  # Filter out the IPs from QUIC.cloud that are actually whitelisted
  IPsToDelete=()
  for IP in $EXISTING_WHITELISTED_IPS; do
    if echo "$QUIC_CLOUD_IPS" | grep -q "$IP"; then
      IPsToDelete+=($IP)
    fi
  done

  # Adjust total IPs to be deleted based on what actually needs deletion
  totalIPs=${#IPsToDelete[@]}
  progress=0
  totalIPsDeleted=0

  # Loop through IPs to delete them from Cloudflare
  for IP in "${IPsToDelete[@]}"; do
    # Get the rule ID for the IP
    RULE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json" | jq -r --arg IP "$IP" '.result[] | select(.configuration.value == $IP) | .id')

    # Delete the rule
    DELETE_RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules/$RULE_ID" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json")

    # Check if the delete request was successful
    if echo "$DELETE_RESPONSE" | jq -e '.success == true' > /dev/null; then
      ((totalIPsDeleted++))
    fi

    # Increment progress and show the progress bar
    ((progress++))
    show_progress
  done

  # Print final message for deletion
  if [ "$totalIPsDeleted" -gt 0 ]; then
    box_message_delete=$(cat <<EOF
Successfully deleted $totalIPsDeleted relevant IP addresses from the whitelist at CF WAF.
EOF
    )
  else
    box_message_delete=$(cat <<EOF
No relevant IP addresses found to delete from the whitelist at CF WAF.
EOF
    )
  fi

  print_box "$box_message_delete"
else
  # If not deleting, proceed with whitelisting
  EXISTING_WHITELISTED_IPS=$(get_whitelisted_ips)

  # Filter out the IPs from QUIC.cloud that are not yet whitelisted
  IPsToWhitelist=()
  totalIPsSkipped=0  # Initialize counter for already whitelisted IPs
  totalIPsFailed=0   # Initialize counter for failed IPs

  # Loop through the QUIC.cloud IPs
  for IP in $(echo "$QUIC_CLOUD_IPS" | jq -r '.[]'); do
    if echo "$EXISTING_WHITELISTED_IPS" | grep -q "$IP"; then
      # IP is already whitelisted, so we skip it
      ((totalIPsSkipped++))
    else
      # IP is not whitelisted, so we add it to the list for whitelisting
      IPsToWhitelist+=($IP)
    fi
  done

  # Adjust total IPs to be whitelisted based on what needs whitelisting
  totalIPs=${#IPsToWhitelist[@]}
  progress=0
  totalIPsAdded=0  # Counter for successfully added IPs

  echo "Whitelisting QUIC.cloud IPs, please wait..."
  for IP in "${IPsToWhitelist[@]}"; do
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json" \
      --data '{
        "mode":"whitelist",
        "configuration": {
          "target": "ip",
          "value": "'"$IP"'"
        },
        "notes": "Whitelist QUIC.cloud IP"
      }')

    # Check if the request was successful
    if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
      ((totalIPsAdded++))
    else
      ((totalIPsFailed++))  # Increment failed IPs counter if something goes wrong
    fi

    # Increment progress and show progress bar
    ((progress++))
    show_progress
  done

  # New line after the progress bar
  echo ""

  # Output the final result for whitelisting
  box_message_whitelist=$(cat <<EOF
Successfully added $totalIPsAdded new IP addresses to the whitelist at CF WAF.
$totalIPsSkipped IP addresses were already whitelisted.
$totalIPsFailed IP addresses could not be added due to errors.
EOF
)

  print_box "$box_message_whitelist"
fi
