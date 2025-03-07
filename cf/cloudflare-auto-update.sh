#!/bin/bash

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Attempting to install jq..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y jq
  elif command -v yum &> /dev/null; then
    sudo yum install -y jq
  else
    echo "Error: Package manager not found. Please install jq manually."
    exit 1
  fi
fi

CONFIG_FILE="config.json"
CONFIG_DIR="$HOME/.cloudflare-auto-update"
CONFIG_PATH="$CONFIG_DIR/$CONFIG_FILE"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Function to prompt for credentials and save them
configure_credentials() {
  echo -e "\nPlease enter your Cloudflare credentials:"
  read -p "Cloudflare Email: " CF_EMAIL
  read -p "Cloudflare API Key: " CF_API_KEY
  read -p "Cloudflare Zone ID: " CF_ZONE_ID

  validate_credentials "$CF_EMAIL" "$CF_API_KEY" "$CF_ZONE_ID"
  if [ $? -ne 0 ]; then
    echo "Credential validation failed. Configuration not saved."
    exit 1
  fi

  ENCODED_EMAIL=$(echo -n "$CF_EMAIL" | base64)
  ENCODED_API_KEY=$(echo -n "$CF_API_KEY" | base64)
  ENCODED_ZONE_ID=$(echo -n "$CF_ZONE_ID" | base64)

  cat > "$CONFIG_PATH" <<EOF
{
  "email": "$ENCODED_EMAIL",
  "api_key": "$ENCODED_API_KEY",
  "zone_id": "$ENCODED_ZONE_ID"
}
EOF

  if [ $? -eq 0 ]; then
    echo -e "\nConfig saved to $CONFIG_PATH\n"
  else
    echo "Error: Failed to save config to $CONFIG_PATH"
    exit 1
  fi
}

# Function to load credentials
load_credentials() {
  if [ ! -f "$CONFIG_PATH" ]; then
    echo "Config file not found at $CONFIG_PATH. Please configure credentials."
    configure_credentials
  else
    CF_EMAIL=$(jq -r '.email' "$CONFIG_PATH" | base64 -d)
    CF_API_KEY=$(jq -r '.api_key' "$CONFIG_PATH" | base64 -d)
    CF_ZONE_ID=$(jq -r '.zone_id' "$CONFIG_PATH" | base64 -d)
  fi
}

# Function to validate Cloudflare credentials
validate_credentials() {
  local email="$1"
  local api_key="$2"
  local zone_id="$3"

  if [ -z "$email" ] || [ -z "$api_key" ] || [ -z "$zone_id" ]; then
    echo -e "\nAuthentication error: One or more credential inputs are empty.\n"
    return 1
  fi

  AUTH_TEST_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id" \
    -H "X-Auth-Email: $email" \
    -H "X-Auth-Key: $api_key" \
    -H "Content-Type: application/json")

  if echo "$AUTH_TEST_RESPONSE" | jq -e '.success != true' > /dev/null; then
    echo -e "\nAuthentication error: Invalid Cloudflare credentials.\n"
    return 1
  fi
  return 0
}

# Check for --configure flag
if [[ "$1" == "--configure" ]]; then
  configure_credentials
  exit 0
fi

# Load credentials
load_credentials

# URL to fetch QUIC.cloud IPs
QUIC_CLOUD_IPS_URL="https://quic.cloud/ips?json"

# Check if URL is accessible
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$QUIC_CLOUD_IPS_URL")
if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "Error: Unable to access QUIC.cloud IPs (HTTP status: $HTTP_STATUS)."
  exit 1
fi

# Get QUIC.cloud IPs
QUIC_CLOUD_IPS=$(curl -s "$QUIC_CLOUD_IPS_URL")

# Function to get all allowlisted IPs (with pagination support)
get_allowlisted_ips() {
  local page=1
  local all_ips=()
  
  while true; do
    # Fetch the allowlisted IPs from Cloudflare, with pagination support
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules?page=$page&per_page=50&mode=whitelist" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json")

    # Parse the IPs from the response
    ips=$(echo "$response" | jq -r '.result[] | .configuration.value')

    # Add the IPs to the all_ips array
    all_ips+=($ips)

    # Check if we have more pages to fetch
    total_pages=$(echo "$response" | jq -r '.result_info.total_pages')
    if [ "$page" -ge "$total_pages" ]; then
      break
    fi
    ((page++))
  done

  # Return all allowlisted IPs
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

# Current date for notes
CURRENT_DATE=$(date +%Y-%m-%d)

# Check if the deletion action is specified
if [[ "$1" == "delete" ]]; then
  echo "Deleting QUIC.cloud IPs, please wait..."

  # Fetch all allowlisted IPs with pagination
  EXISTING_ALLOWLISTED_IPS=$(get_allowlisted_ips)

  # Filter out the IPs from QUIC.cloud that are actually allowlisted
  IPsToDelete=()
  for IP in $EXISTING_ALLOWLISTED_IPS; do
    if echo "$QUIC_CLOUD_IPS" | grep -q "$IP"; then
      IPsToDelete+=("$IP")
    fi
  done
  
  # Adjust total IPs to be deleted based on what actually needs deletion
  totalIPs=${#IPsToDelete[@]}
  progress=0
  totalIPsDeleted=0

  for IP in "${IPsToDelete[@]}"; do
    # Get the rule ID for the IP
    RULE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules?configuration.value=$IP" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ -n "$RULE_ID" ] && [ "$RULE_ID" != "null" ]; then
      # Delete the rule
      DELETE_RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules/$RULE_ID" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_API_KEY" \
        -H "Content-Type: application/json")

       # Check if the delete request was successful
      if echo "$DELETE_RESPONSE" | jq -e '.success == true' > /dev/null; then
        ((totalIPsDeleted++))
      fi
    fi
    
    # Increment progress and show the progress bar
    ((progress++))
    show_progress
  done
  
  # Print final message for deletion
  box_message_delete=$(cat <<EOF
Successfully deleted $totalIPsDeleted relevant IP addresses from the allowlist at CF WAF.
EOF
    )
  print_box "$box_message_delete"
else
  # If not deleting, proceed with allowlisting
  EXISTING_ALLOWLISTED_IPS=$(get_allowlisted_ips)

  # Filter out the IPs from QUIC.cloud that are not yet allowlisted
  IPsToWhitelist=() 
  totalIPsSkipped=0 # Initialize counter for already allowlisted IPs
  totalIPsFailed=0 # Initialize counter for failed IPs

  # Loop through the QUIC.cloud IPs
  for IP in $(echo "$QUIC_CLOUD_IPS" | jq -r '.[]'); do
    if echo "$EXISTING_ALLOWLISTED_IPS" | grep -q "$IP"; then
      ((totalIPsSkipped++))
    else
      # IP is not allowlisted, so we add it to the list for allowlisting
      IPsToWhitelist+=("$IP")
    fi
  done

  # Adjust total IPs to be allowlisted based on what needs allowlisting
  totalIPs=${#IPsToWhitelist[@]}
  progress=0
  totalIPsAdded=0 # Counter for successfully added IPs

  echo "Whitelisting QUIC.cloud IPs, please wait..."
  for IP in "${IPsToWhitelist[@]}"; do
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json" \
      --data '{
        "mode": "whitelist",
        "configuration": {
          "target": "ip",
          "value": "'"$IP"'"
        },
        "notes": "QUIC.cloud IP, IP allowed on '"$CURRENT_DATE"'"
      }')

    # Check if the request was successful
    if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
      ((totalIPsAdded++))
    else
      ((totalIPsFailed++)) # Increment failed IPs counter if something goes wrong
    fi
    
    # Increment progress and show progress bar
    ((progress++))
    show_progress
  done

  # New line after the progress bar
  echo ""
  
  # Output the final result for allowlisting
  box_message_allowlist=$(cat <<EOF
Successfully added $totalIPsAdded new IP addresses to the allowlist at CF WAF.
$totalIPsSkipped IP addresses were already allowlisted.
$totalIPsFailed IP addresses could not be added due to errors.
EOF
)
  print_box "$box_message_allowlist"
fi
