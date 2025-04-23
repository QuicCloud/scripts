
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
QUIC_CLOUD_IPS=$(curl -s "$QUIC_CLOUD_IPS_URL" | jq -r '.[]')

# Function to get all allowlisted rules added by this script
get_script_managed_rules() {
  local page=1
  local ids=()

  while true; do
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules?page=$page&per_page=50" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json")

    ids+=($(echo "$response" | jq -r '.result[] | select(.notes | test("QUIC.cloud IP, IP allowed on ")) | .id'))

    total_pages=$(echo "$response" | jq -r '.result_info.total_pages')
    if [ "$page" -ge "$total_pages" ]; then
      break
    fi
    ((page++))
  done

  echo "${ids[@]}"
}

# Function to get rule IPs added by this script
get_script_managed_ips() {
  local page=1
  local ips=()

  while true; do
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules?page=$page&per_page=50" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json")

    ips+=($(echo "$response" | jq -r '.result[] | select(.notes | test("QUIC.cloud IP, IP allowed on ")) | .configuration.value'))

    total_pages=$(echo "$response" | jq -r '.result_info.total_pages')
    if [ "$page" -ge "$total_pages" ]; then
      break
    fi
    ((page++))
  done

  echo "${ips[@]}"
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
  max_length=$(echo "$message" | awk '{ if (length > L) L = length } END { print L }')
  echo -e "\n+$(printf "%0.s-" $(seq 1 $((max_length + 2))))+"
  while IFS= read -r line; do
    printf "| %-*s |\n" "$max_length" "$line"
  done <<< "$message"
  echo -e "+$(printf "%0.s-" $(seq 1 $((max_length + 2))))+\n"
}

# Current date for notes
CURRENT_DATE=$(date +%Y-%m-%d)

# Handle delete all mode
if [[ "$1" == "delete" ]]; then
  echo "Deleting all QUIC.cloud IPs added by this script..."
  SCRIPT_MANAGED_RULE_IDS=($(get_script_managed_rules))
  totalIPs=${#SCRIPT_MANAGED_RULE_IDS[@]}
  progress=0
  totalDeleted=0

  if [ "$totalIPs" -eq 0 ]; then
    echo "No QUIC.cloud IPs found to delete."
  else
    for i in "${!SCRIPT_MANAGED_RULE_IDS[@]}"; do
      ID="${SCRIPT_MANAGED_RULE_IDS[$i]}"
      RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules/$ID" \
        -H "X-Auth-Email: $CF_EMAIL" \
        -H "X-Auth-Key: $CF_API_KEY" \
        -H "Content-Type: application/json")
      if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
        ((totalDeleted++))
      fi
      ((progress++))
      show_progress
    done
    print_box "Successfully deleted $totalDeleted QUIC.cloud IPs from the CF WAF."
  fi
  exit 0
fi

# Remove outdated IPs
echo "Removing outdated IPs..."
CURRENT_MANAGED_IPS=($(get_script_managed_ips))
IPsToRemove=()

for ip in "${CURRENT_MANAGED_IPS[@]}"; do
  if ! echo "$QUIC_CLOUD_IPS" | grep -qw "$ip"; then
    ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules?configuration.value=$ip" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json" | jq -r '.result[0].id')
    [ -n "$ID" ] && [ "$ID" != "null" ] && IPsToRemove+=("$ID")
  fi
done

progress=0
totalIPs=${#IPsToRemove[@]}
removed=0

if [ "$totalIPs" -eq 0 ]; then
  echo "No outdated IPs to remove."
else
  for id in "${IPsToRemove[@]}"; do
    RESPONSE=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules/$id" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json")
    if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
      ((removed++))
    fi
    ((progress++))
    show_progress
  done
fi

# Add new IPs
echo -e "\nAdding new IPs..."
IPsToAdd=()
for ip in $QUIC_CLOUD_IPS; do
  if ! echo "${CURRENT_MANAGED_IPS[@]}" | grep -qw "$ip"; then
    IPsToAdd+=("$ip")
  fi
done

progress=0
totalIPs=${#IPsToAdd[@]}
added=0

if [ "$totalIPs" -eq 0 ]; then
  echo "No new IPs to add."
else
  for ip in "${IPsToAdd[@]}"; do
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/firewall/access_rules/rules" \
      -H "X-Auth-Email: $CF_EMAIL" \
      -H "X-Auth-Key: $CF_API_KEY" \
      -H "Content-Type: application/json" \
      --data '{
        "mode": "whitelist",
        "configuration": {
          "target": "ip",
          "value": "'"$ip"'"
        },
        "notes": "QUIC.cloud IP, IP allowed on '"$CURRENT_DATE"'"
      }')
    if echo "$RESPONSE" | jq -e '.success == true' > /dev/null; then
      ((added++))
    fi
    ((progress++))
    show_progress
  done
fi

# Summary output
print_box "Successfully added $added IPs and removed $removed outdated IPs from CF WAF."
