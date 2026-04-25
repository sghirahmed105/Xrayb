#!/usr/bin/env bash
set -euo pipefail

# ========== LOAD PROTOCOL LIBRARY ==========
# Source the unified protocol library to reduce code duplication
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib_protocols.sh"

# ========== COLOR CODES & FORMATTING ==========
# Primary Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'

# Bright/Light Colors
BRIGHT_RED='\033[0;91m'
BRIGHT_GREEN='\033[0;92m'
BRIGHT_YELLOW='\033[0;93m'
BRIGHT_BLUE='\033[0;94m'
BRIGHT_CYAN='\033[0;96m'
BRIGHT_MAGENTA='\033[0;95m'
BRIGHT_WHITE='\033[0;97m'

# Text Formatting
BOLD='\033[1m'
UNDERLINE='\033[4m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Background Colors
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_CYAN='\033[46m'
BG_MAGENTA='\033[45m'

# ========== REQUIRED GCP APIs ==========
# List of all APIs required for this script to function
declare -A REQUIRED_APIS=(
  [run]="run.googleapis.com|Cloud Run"
  [cloudbuild]="cloudbuild.googleapis.com|Cloud Build"
  [orgpolicy]="orgpolicy.googleapis.com|Org Policy"
  [compute]="compute.googleapis.com|Compute Engine"
)

# ========== UTILITY FUNCTIONS ==========
print_header() {
  echo -e "\n${BRIGHT_CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                                  ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}   ${BRIGHT_GREEN}🚀 XRAY Cloud Run Deployment Tool${NC}   ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}         ${BRIGHT_MAGENTA}(VLESS / VMESS / TROJAN)${NC}              ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                                  ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_section() {
  local title=$1
  echo -e "\n${BRIGHT_BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BRIGHT_BLUE}${BOLD}▶${NC} ${BRIGHT_WHITE}${BOLD}${title}${NC}"
  echo -e "${BRIGHT_BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
  echo -e "${BRIGHT_GREEN}${BOLD}✓${NC} ${GREEN}$1${NC}"
}

print_error() {
  echo -e "${BRIGHT_RED}${BOLD}✗${NC} ${RED}$1${NC}"
}

print_info() {
  echo -e "${BRIGHT_CYAN}${BOLD}ℹ${NC} ${CYAN}$1${NC}"
}

print_warning() {
  echo -e "${BRIGHT_YELLOW}${BOLD}⚠${NC} ${YELLOW}$1${NC}"
}

print_highlight() {
  echo -e "${BOLD}${BRIGHT_MAGENTA}$1${NC}"
}

separator() {
  echo -e "${GRAY}${DIM}───────────────────────────────────────────────────${NC}"
}

# Detect interactive mode (has a TTY). When non-interactive (e.g. `curl | bash`),
# the script will read configuration from environment variables or use defaults.
if [ -t 0 ] && [ -t 1 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# -------- Enable All Required GCP APIs (First Priority) --------
enable_required_apis() {
  # This function is defined below and called immediately
  print_section "Enabling Required GCP Services"
  
  if ! command -v gcloud >/dev/null 2>&1; then
    print_error "gcloud CLI not found. Install and authenticate first."
    exit 1
  fi
  print_success "gcloud CLI found"
  
  PROJECT=$(gcloud config get-value project 2>/dev/null || true)
  if [ -z "${PROJECT:-}" ]; then
    print_error "No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
    exit 1
  fi
  print_success "GCP Project: ${BRIGHT_CYAN}${PROJECT}${NC}"
  
  echo ""
  print_info "Checking and enabling required APIs..."
  echo ""
  
  # Get list of currently enabled APIs
  ENABLED_APIS=$(gcloud services list --enabled --format="value(name)" 2>/dev/null || true)
  
  # Track which APIs need to be enabled
  APIS_TO_ENABLE=()
  
  # Check each required API
  for api_key in "${!REQUIRED_APIS[@]}"; do
    IFS='|' read -r api_name api_display <<< "${REQUIRED_APIS[$api_key]}"
    
    if echo "$ENABLED_APIS" | grep -q "$api_name"; then
      echo -e "  ${BRIGHT_GREEN}✓${NC} ${BOLD}${api_display}${NC} ${DIM}(${api_name})${NC} ${GREEN}Already enabled${NC}"
    else
      echo -e "  ${BRIGHT_YELLOW}→${NC} ${BOLD}${api_display}${NC} ${DIM}(${api_name})${NC} ${YELLOW}Will be enabled${NC}"
      APIS_TO_ENABLE+=("$api_name")
    fi
  done
  
  # Enable APIs that are not yet enabled
  if [ ${#APIS_TO_ENABLE[@]} -gt 0 ]; then
    echo ""
    print_info "Enabling ${BRIGHT_CYAN}${#APIS_TO_ENABLE[@]} API(s)${NC}..."
    echo ""
    
    if gcloud services enable "${APIS_TO_ENABLE[@]}" --quiet 2>/dev/null; then
      echo ""
      delimiter="════════════════════════════════════════════════════════"
      echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
      print_success "All required APIs have been enabled successfully"
      echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
    else
      echo ""
      print_error "Failed to enable some APIs. Please check your permissions."
      echo -e "${YELLOW}You may need to manually enable these APIs:${NC}"
      for api in "${APIS_TO_ENABLE[@]}"; do
        echo -e "  ${BRIGHT_YELLOW}•${NC} ${BOLD}${api}${NC}"
      done
      exit 1
    fi
  else
    echo ""
    delimiter="════════════════════════════════════════════════════════"
    echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
    print_success "All required APIs are already enabled"
    echo -e "${BRIGHT_GREEN}${BOLD}${delimiter}${NC}"
  fi
  
  echo ""
}

# Enable all required APIs FIRST (before anything else)
enable_required_apis

# Print formatted header (after APIs are enabled)
print_header

# -------- Store Session Start Time (from last system reboot) --------
# Extract the last reboot time to track when the system was last started
SESSION_START_TIME=""

if command -v last >/dev/null 2>&1; then
  # Get the last reboot information
  reboot_info=$(last reboot 2>/dev/null | head -1 || true)
  if [ -n "$reboot_info" ]; then
    # Extract datetime from last reboot output (format: YYYY-MM-DD HH:MM)
    reboot_dt=$(echo "$reboot_info" | sed -nE 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}).*/\1/p' || true)
    if [ -n "$reboot_dt" ]; then
      SESSION_START_TIME=$(date -d "$reboot_dt" "+%s" 2>/dev/null || date "+%s")
    else
      SESSION_START_TIME=$(date "+%s")
    fi
  else
    SESSION_START_TIME=$(date "+%s")
  fi
else
  SESSION_START_TIME=$(date "+%s")
fi

# -------- Preset Configurations --------
declare -A PRESETS=(
  [production]="memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [budget]="memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [trojan-ws]="proto=trojan|path=/|sni=yt3.ggpht.com|alpn=default|memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [vless-ws]="proto=vless|path=/|sni=yt3.ggpht.com|alpn=default|memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [vmess-ws]="proto=vmess|path=/|sni=yt3.ggpht.com|alpn=default|memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
)

# Generate random 4-character lowercase service name
generate_random_service_name() {
  local chars="abcdefghijklmnopqrstuvwxyz"
  local name=""
  for i in {1..4}; do
    name="${name}${chars:$((RANDOM % ${#chars})):1}"
  done
  echo "${name}-ws"
}

apply_preset() {
  local preset=$1
  if [[ -v PRESETS[$preset] ]]; then
    local config="${PRESETS[$preset]}"
    IFS='|' read -ra settings <<< "$config"
    for setting in "${settings[@]}"; do
      IFS='=' read -r key value <<< "$setting"
      case "$key" in
        memory) MEMORY="$value" ;;
        cpu) CPU="$value" ;;
        instances) MAX_INSTANCES="$value" ;;
        concurrency) CONCURRENCY="$value" ;;
        timeout) TIMEOUT="$value" ;;
        proto) PRESET_PROTO="$value" ;;
        path) PRESET_WSPATH="$value" ;;
        sni) PRESET_SNI="$value" ;;
        alpn) PRESET_ALPN="$value" ;;
      esac
    done
    # Generate random service name for protocol presets
    if [[ "$preset" =~ ^(trojan-ws|vless-ws|vmess-ws)$ ]]; then
      PRESET_SERVICE="$(generate_random_service_name)"
    fi
  fi
}

# Suggested short list of regions (user will choose by index)
SUGGESTED_REGIONS=(
  us-central1
  us-east1
  us-east4
  us-west1
  europe-west1
  europe-west4
  
 
)

# Additional regions for the "more" option
MORE_REGIONS=(
  # USA Regions
  us-east5
  us-west2
  us-west3
  us-west4
  us-south1
  # North America Regions
  northamerica-northeast1
  northamerica-northeast2
  # South America Regions
  southamerica-east1
  # Europe Regions
  europe-north1
  europe-central2
  europe-southwest1
  europe-west2
  europe-west6
  europe-west8
  europe-west9
  europe-west10
  europe-west12
  # Asia Regions
  asia-east1
  asia-east2
  asia-northeast1
  asia-south1
  asia-southeast1
  asia-northeast2
  asia-northeast3
  # Africa & Middle East Regions
  africa-south1
  me-west1
  # Oceania Regions
   australia-southeast1
)

show_regions() {
  echo ""
  echo "🌍 Suggested Cloud Run Regions (pick one):"
  echo ""
  AVAILABLE=""
  if command -v gcloud >/dev/null 2>&1; then
    AVAILABLE=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)
  fi

  i=1
  for r in "${SUGGESTED_REGIONS[@]}"; do
    region_name="$(get_region_name "$r")"
    if [ -n "$AVAILABLE" ] && echo "$AVAILABLE" | grep -xq "$r"; then
      printf "%2d) %s (%s) (available)\n" "$i" "$r" "$region_name"
    else
      printf "%2d) %s (%s)\n" "$i" "$r" "$region_name"
    fi
    ((i++))
  done
  echo ""
  printf "%2d) %s (Show more regions)\n" "$i" "more"
}

show_more_regions() {
  echo ""
  echo "🌍 More Cloud Run Regions:"
  echo ""
  AVAILABLE=""
  if command -v gcloud >/dev/null 2>&1; then
    AVAILABLE=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)
  fi

  i=1
  for r in "${MORE_REGIONS[@]}"; do
    region_name="$(get_region_name "$r")"
    if [ -n "$AVAILABLE" ] && echo "$AVAILABLE" | grep -xq "$r"; then
      printf "%2d) %s (%s) (available)\n" "$i" "$r" "$region_name"
    else
      printf "%2d) %s (%s)\n" "$i" "$r" "$region_name"
    fi
    ((i++))
  done
}

deploy_service() {
  # -------- Protocol Selection --------
  select_protocol_interactive || return 1

  # -------- Network Type --------
  # Cloud Run supports WebSocket (ws) reliably; gRPC has compatibility issues
  NETWORK="ws"
  NETWORK_DISPLAY="WebSocket"

  # -------- WebSocket Path --------
  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${WSPATH:-}" ]; do
      read -rp "$(echo -e "${BOLD}📡 WebSocket Path${NC} (required): ")" WSPATH
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${WSPATH:-}" ]; then
      # Use preset path if available, otherwise ask
      if [ -z "${PRESET_WSPATH:-}" ]; then
        read -rp "$(echo -e "${BOLD}📡 WebSocket Path${NC} (default: /ws): ")" WSPATH
      else
        WSPATH="${PRESET_WSPATH}"
        print_info "WebSocket Path (from preset): $WSPATH"
      fi
    fi
    WSPATH="${WSPATH:-${PRESET_WSPATH:-/ws}}"
  fi

  # -------- Service Name --------
  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${SERVICE:-}" ]; do
      read -rp "$(echo -e "${BOLD}🪪 Cloud Run Service Name${NC} (required): ")" SERVICE
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${SERVICE:-}" ]; then
      # Use preset service if available, otherwise ask
      if [ -z "${PRESET_SERVICE:-}" ]; then
        read -rp "$(echo -e "${BOLD}🪪 Cloud Run Service Name${NC} (default: xray-ws): ")" SERVICE
      else
        SERVICE="${PRESET_SERVICE}"
        print_info "Service Name (from preset): $SERVICE"
      fi
    fi
    SERVICE="${SERVICE:-${PRESET_SERVICE:-xray-ws}}"
  fi

  # -------- Advanced Settings --------
  if [ "$PRESET_MODE" = "custom" ]; then
    print_section "Advanced Settings"
    echo ""
    echo -e "  ${BOLD}1${NC} yt3.ggpht.com    (YouTube CDN - Recommended)"
    echo -e "  ${BOLD}2${NC} www.google.com   (Google CDN)"
    echo -e "  ${BOLD}3${NC} youtube.com  (YouTube Direct)"
    echo -e "  ${BOLD}4${NC} ${GRAY}(Leave blank)${NC}     No SNI"
    echo ""
    SNI_CHOICE=""
    while [ -z "${SNI_CHOICE:-}" ]; do
      read -rp "$(echo -e "${BOLD}Select SNI [1-4]${NC} (required): ")" SNI_CHOICE
    done
    case "$SNI_CHOICE" in
      1)
        SNI="yt3.ggpht.com"
        print_success "SNI: $SNI"
        ;;
      2)
        SNI="www.google.com"
        print_success "SNI: $SNI"
        ;;
      3)
        SNI="m.youtube.com"
        print_success "SNI: $SNI"
        ;;
      4)
        SNI=""
        print_info "No SNI selected"
        ;;
      *)
        SNI="$SNI_CHOICE"
        print_success "Custom SNI: $SNI"
        ;;
    esac

    echo ""
    echo -e "  ${BOLD}1${NC} default          (h2, http/1.1)"
    echo -e "  ${BOLD}2${NC} h2,http/1.1      (HTTP/2 Priority)"
    echo -e "  ${BOLD}3${NC} h2               (HTTP/2 Only)"
    echo -e "  ${BOLD}4${NC} http/1.1         (HTTP/1.1 Only)"
    echo ""
    ALPN_CHOICE=""
    while [ -z "${ALPN_CHOICE:-}" ]; do
      read -rp "$(echo -e "${BOLD}Select ALPN [1-4]${NC} (required): ")" ALPN_CHOICE
    done
    case "$ALPN_CHOICE" in
      1)
        ALPN="default"
        print_success "ALPN: $ALPN"
        ;;
      2)
        ALPN="h2,http/1.1"
        print_success "ALPN: $ALPN"
        ;;
      3)
        ALPN="h2"
        print_success "ALPN: $ALPN"
        ;;
      4)
        ALPN="http/1.1"
        print_success "ALPN: $ALPN"
        ;;
      *)
        ALPN="$ALPN_CHOICE"
        print_success "Custom ALPN: $ALPN"
        ;;
    esac
  else
    SNI="${PRESET_SNI}"
    ALPN="${PRESET_ALPN}"
  fi

  # -------- Performance Settings --------
  print_section "Performance Configuration"

  if [ "$PRESET_MODE" = "custom" ]; then
    echo -e "${GRAY}(All fields are required)${NC}"
  else
    echo -e "${GRAY}Preset: ${BOLD}$PRESET_MODE${GRAY} (press Enter to keep)${NC}"
  fi

  echo ""

  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${MEMORY:-}" ]; do
      read -rp "$(echo -e "${BOLD}💾 Memory (MB)${NC} (required): ")" MEMORY
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${MEMORY:-}" ]; then
      read -rp "$(echo -e "${BOLD}💾 Memory (MB)${NC} [512/1024/2048]: ")" MEMORY
    fi
    MEMORY="${MEMORY:-}"
  fi

  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${CPU:-}" ]; do
      read -rp "$(echo -e "${BOLD}⚙️  CPU cores${NC} (required): ")" CPU
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${CPU:-}" ]; then
      read -rp "$(echo -e "${BOLD}⚙️  CPU cores${NC} [0.5/1/2]: ")" CPU
    fi
    CPU="${CPU:-}"
  fi

  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${TIMEOUT:-}" ]; do
      read -rp "$(echo -e "${BOLD}⏱️  Timeout (seconds)${NC} (required): ")" TIMEOUT
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${TIMEOUT:-}" ]; then
      read -rp "$(echo -e "${BOLD}⏱️  Timeout (seconds)${NC} [300/1800/3600]: ")" TIMEOUT
    fi
    TIMEOUT="${TIMEOUT:-}"
  fi

  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${MAX_INSTANCES:-}" ]; do
      read -rp "$(echo -e "${BOLD}📊 Max instances${NC} (required): ")" MAX_INSTANCES
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${MAX_INSTANCES:-}" ]; then
      read -rp "$(echo -e "${BOLD}📊 Max instances${NC} [5/10/20/50]: ")" MAX_INSTANCES
    fi
    MAX_INSTANCES="${MAX_INSTANCES:-}"
  fi

  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${MIN_INSTANCES:-}" ]; do
      read -rp "$(echo -e "${BOLD}📉 Min instances${NC} (required): ")" MIN_INSTANCES
    done
  else
    MIN_INSTANCES="${MIN_INSTANCES:-4}"
  fi

  if [ "$PRESET_MODE" = "custom" ]; then
    echo ""
    echo -e "  ${BOLD}1${NC} gen1   (First generation - faster cold starts)"
    echo -e "  ${BOLD}2${NC} gen2   (Second generation - full Linux, better performance)"
    echo -e "  ${BOLD}Enter${NC} (Default - Cloud Run chooses)"
    echo ""
    read -rp "$(echo -e "${BOLD}Execution Environment${NC} [1/2/Enter]: ")" ENV_CHOICE
    case "$ENV_CHOICE" in
      1) EXEC_ENV="gen1" ;;
      2) EXEC_ENV="gen2" ;;
      *) EXEC_ENV="" ;;
    esac
  else
    EXEC_ENV="gen2"
  fi

  if [ "$PRESET_MODE" = "custom" ]; then
    while [ -z "${CONCURRENCY:-}" ]; do
      read -rp "$(echo -e "${BOLD}🔗 Max concurrent requests${NC} (required): ")" CONCURRENCY
    done
  else
    if [ "${INTERACTIVE}" = true ] && [ -z "${CONCURRENCY:-}" ]; then
      read -rp "$(echo -e "${BOLD}🔗 Max concurrent requests${NC} [100/500/1000]: ")" CONCURRENCY
    fi
    CONCURRENCY="${CONCURRENCY:-}"
  fi

  # Speed Limit: قيمة ثابتة (لا تؤثر حالياً على السرعة الفعلية)
  SPEED_LIMIT="${SPEED_LIMIT:-0}"

  # Show what was selected
  echo ""
  print_section "Configuration Summary"
  echo ""
  [ -n "${MEMORY}" ] && print_success "Memory: ${BOLD}${MEMORY}${NC} MB" || print_info "Memory: (Cloud Run default)"
  [ -n "${CPU}" ] && print_success "CPU: ${BOLD}${CPU}${NC} cores" || print_info "CPU: (Cloud Run default)"
  [ -n "${TIMEOUT}" ] && print_success "Timeout: ${BOLD}${TIMEOUT}${NC}s" || print_info "Timeout: (Cloud Run default)"
  [ -n "${MAX_INSTANCES}" ] && print_success "Max instances: ${BOLD}${MAX_INSTANCES}${NC}" || print_info "Max instances: (Cloud Run default)"
  [ -n "${CONCURRENCY}" ] && print_success "Max concurrency: ${BOLD}${CONCURRENCY}${NC}" || print_info "Max concurrency: (Cloud Run default)"

  # -------- Sanity checks --------
  print_section "Validation"

  if ! command -v gcloud >/dev/null 2>&1; then
    print_error "gcloud CLI not found. Install and authenticate first."
    return 1
  fi
  print_success "gcloud CLI found"

  PROJECT=$(gcloud config get-value project 2>/dev/null || true)
  if [ -z "${PROJECT:-}" ]; then
    print_error "No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
    return 1
  fi
  print_success "GCP Project: $PROJECT"
  print_success "All required APIs are enabled"

  # -------- Deploying XRAY to Cloud Run --------
  print_section "Deploying XRAY to Cloud Run"
  echo ""

  # Get PROJECT_NUMBER early (needed for HOST env var)
  PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project 2>/dev/null) --format="value(projectNumber)" 2>/dev/null)

  # Build deploy command with optional parameters
  DEPLOY_ARGS=(
    "--source" "."
    "--region" "$REGION"
    "--platform" "managed"
    "--allow-unauthenticated"
  )

  [ -n "${MEMORY}" ] && DEPLOY_ARGS+=("--memory" "${MEMORY}Mi")
  [ -n "${CPU}" ] && DEPLOY_ARGS+=("--cpu" "${CPU}")
  [ -n "${TIMEOUT}" ] && DEPLOY_ARGS+=("--timeout" "${TIMEOUT}")
  [ -n "${MAX_INSTANCES}" ] && DEPLOY_ARGS+=("--max-instances" "${MAX_INSTANCES}")
  DEPLOY_ARGS+=("--min-instances" "${MIN_INSTANCES:-4}")
  [ -n "${EXEC_ENV}" ] && DEPLOY_ARGS+=("--execution-environment" "${EXEC_ENV}")
  [ -n "${CONCURRENCY}" ] && DEPLOY_ARGS+=("--concurrency" "${CONCURRENCY}")

  # Speed limit is now configured interactively or via environment variable

  # Use Cloud Run service URL as WebSocket host header
  # Format: service-projectnumber.region.run.app
  DEPLOY_ARGS+=("--set-env-vars" "PROTO=${PROTO},USER_ID=${UUID},WS_PATH=${WSPATH},NETWORK=${NETWORK},SPEED_LIMIT=${SPEED_LIMIT},HOST=${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app")
  DEPLOY_ARGS+=("--quiet")

  # -------- Get URL --------
  gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}"

  # -------- Get URL and Host --------

  # Use custom hostname if provided, otherwise use Cloud Run default
  if [ -n "${CUSTOM_HOST}" ]; then
    HOST="${CUSTOM_HOST}"
    echo "Service URL: https://${HOST}"
    echo "✅ Using custom hostname: ${HOST}"
  else
    HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
    echo "Service URL: https://${HOST}"
    echo "✅ Using Cloud Run default: ${HOST}"
  fi

  # -------- Get URL and Host --------

  # Use custom hostname if provided, otherwise use Cloud Run default
  if [ -n "${CUSTOM_HOST}" ]; then
    HOST="${CUSTOM_HOST}"
    echo "Service URL: https://${HOST}"
    print_success "Using custom hostname: ${HOST}"
  else
    HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
    echo ""
    print_success "Service deployed successfully!"
    echo "Service URL: ${BOLD}https://${HOST}${NC}"
  fi

  # -------- Output --------
  echo ""
  echo -e "${BRIGHT_GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}║${NC}              ✅ ${BRIGHT_WHITE}${BOLD}DEPLOYMENT SUCCESS${NC}               ${BRIGHT_GREEN}${BOLD}║${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  echo -e "  ${BRIGHT_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}Protocol${NC}:       ${BRIGHT_GREEN}${PROTO^^}${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}Address${NC}:       ${BRIGHT_CYAN}${HOST}${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}Port${NC}:          ${BRIGHT_YELLOW}443${NC} ${DIM}(HTTPS)${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}UUID/PWD${NC}:      ${BRIGHT_MAGENTA}${UUID}${NC}"

  if [ "$NETWORK" = "ws" ]; then
    echo -e "  ${BOLD}${BRIGHT_CYAN}Path${NC}:          ${BRIGHT_BLUE}${WSPATH}${NC}"
  elif [ "$NETWORK" = "grpc" ]; then
    echo -e "  ${BOLD}${BRIGHT_CYAN}Service${NC}:       ${BRIGHT_BLUE}${WSPATH}${NC}"
  fi

  echo -e "  ${BOLD}${BRIGHT_CYAN}Network${NC}:       ${BRIGHT_CYAN}${NETWORK_DISPLAY}${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}Security${NC}:      ${BRIGHT_GREEN}TLS${NC} ${DIM}(Enabled)${NC}"

  if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
    MBPS=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
    echo -e "  ${BOLD}${BRIGHT_CYAN}Speed Limit${NC}:   ${BRIGHT_YELLOW}${SPEED_LIMIT} KB/s${NC} ${DIM}(~${MBPS} Mbps)${NC}"
  else
    echo -e "  ${BOLD}${BRIGHT_CYAN}Speed Limit${NC}:   ${BRIGHT_YELLOW}${SPEED_LIMIT}${NC}"
  fi

  if [ -n "${MEMORY}${CPU}${TIMEOUT}${MAX_INSTANCES}${CONCURRENCY}" ]; then
    echo ""
    echo -e "  ${BRIGHT_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}${BRIGHT_BLUE}⚙️  Configuration Applied${NC}:"
    [ -n "${MEMORY}" ] && echo -e "      ${DIM}├─${NC} Memory:        ${BRIGHT_GREEN}${MEMORY}${NC} MB"
    [ -n "${CPU}" ] && echo -e "      ${DIM}├─${NC} CPU:           ${BRIGHT_GREEN}${CPU}${NC} cores"
    [ -n "${TIMEOUT}" ] && echo -e "      ${DIM}├─${NC} Timeout:       ${BRIGHT_GREEN}${TIMEOUT}${NC}s"
    [ -n "${MAX_INSTANCES}" ] && echo -e "      ${DIM}├─${NC} Max Instances: ${BRIGHT_GREEN}${MAX_INSTANCES}${NC}"
    [ -n "${CONCURRENCY}" ] && echo -e "      ${DIM}└─${NC} Concurrency:   ${BRIGHT_GREEN}${CONCURRENCY}${NC} req/instance"
  fi

  echo ""
  echo -e "${BRIGHT_CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                              ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}              📎 ${BRIGHT_WHITE}${BOLD}SHARED LINKS${NC}                    ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                              ${BRIGHT_CYAN}${BOLD}║${NC}"
  echo -e "${BRIGHT_CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"

  # -------- Build Query Parameters --------
  # Build query parameters for WebSocket (only supported on Cloud Run)
  QUERY_PARAMS="type=ws&security=tls&path=${WSPATH}"
  if [ -n "${SNI}" ]; then
    QUERY_PARAMS="${QUERY_PARAMS}&sni=${SNI}"
  fi
  if [ -n "${ALPN}" ]; then
    QUERY_PARAMS="${QUERY_PARAMS}&alpn=${ALPN}"
  fi
  # Add host parameter for WebSocket compatibility
  QUERY_PARAMS="${QUERY_PARAMS}&host=${HOST}"

  # Build fragment with custom ID
  LINK_FRAGMENT="xray"
  if [ -n "${CUSTOM_ID}" ]; then
    LINK_FRAGMENT="(${CUSTOM_ID})"
  fi

  # -------- Generate Protocol Links --------
  # Generate primary link using unified function
  SHARE_LINK="$(build_protocol_link "$PROTO" "$HOST" "443" "$QUERY_PARAMS" "$LINK_FRAGMENT")"
  print_protocol_link "$PROTO" "$SHARE_LINK"

  # -------- Generate Alternative URL (short URL) --------
  # Try to get the short URL from gcloud (if available)
  ALT_HOST=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)" 2>/dev/null | sed 's|https://||' | sed 's|/||g' || echo "")

  if [ -z "$ALT_HOST" ]; then
    ALT_HOST="$HOST"  # fallback to primary if short URL not available
  fi

  # Generate alternative link with short URL only if different from primary
  if [ "$ALT_HOST" != "$HOST" ]; then
    # use friendly region name for fragment (fallback to code if not known)
    friendly_region="$(get_region_name "$REGION")"
    # add "-alt" suffix when building alt fragments to indicate the short URL
    friendly_region_alt="${friendly_region}_SN"

    if [ "$PROTO" = "vless" ] || [ "$PROTO" = "trojan" ]; then
      alt_query=$(echo "$QUERY_PARAMS" | sed 's/&host=[^&]*//g')
      alt_query="${alt_query}&host=${HOST}"
      ALT_LINK="$(build_protocol_link "$PROTO" "$ALT_HOST" "443" "$alt_query" "${friendly_region_alt}")"
    elif [ "$PROTO" = "vmess" ]; then
      # For VMESS, rebuild with ALT_HOST
      vmess_for_alt=$(echo "$VMESS_JSON" | sed "s|\"add\": \"$HOST\"|\"add\": \"$ALT_HOST\"|")
      ALT_LINK="vmess://$(echo "$vmess_for_alt" | base64 -w 0)"
    fi
    
    echo ""
    echo -e "${BOLD}${WHITE}Alternative Link (Short URL):${NC}"
    echo "$ALT_LINK"
  else
    ALT_LINK="$SHARE_LINK"
  fi

  echo ""
  echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════╝${NC}"

  # -------- Generate Data URIs --------
  echo ""
  print_section "Data URIs (JSON/Text)"
  echo ""

  # Data URI 1: Plain text configuration
  CONFIG_TEXT="$(build_config_text)"
  DATA_URI_TEXT="data:text/plain;base64,$(echo -n "$CONFIG_TEXT" | base64 -w 0)"
  echo -e "${BOLD}Text Format:${NC}"
  echo "$DATA_URI_TEXT"
  echo ""

  # Data URI 2: JSON configuration
  CONFIG_JSON="$(build_config_json "$NETWORK")"

  DATA_URI_JSON="data:application/json;base64,$(echo -n "$CONFIG_JSON" | base64 -w 0)"
  echo -e "${BOLD}JSON Format:${NC}"
  echo "$DATA_URI_JSON"

  echo "$DATA_URI_JSON"
  echo ""

  # -------- Send to Telegram --------
  if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
    print_section "Sending to Telegram"
    # Send primary link (primary URL in HOST)
    #send_telegram "<b>🔗 PRIMARY (HOST):</b><pre>${SHARE_LINK}</pre>" 
    send_telegram "<b>🔗 PRIMARY (HOST):</b><pre>${ALT_LINK}</pre>"
    print_success "Configuration sent to Telegram"
  fi

  echo ""
  echo -e "${BRIGHT_GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}║${NC}    ✓ ${BRIGHT_WHITE}${BOLD}Installation Completed Successfully${NC}             ${BRIGHT_GREEN}${BOLD}║${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
  echo -e "${BRIGHT_GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BRIGHT_YELLOW}${BOLD}📌 Next Steps:${NC}"
  echo -e "  ${BRIGHT_CYAN}1.${NC} Copy the link above (VLESS, VMESS, or TROJAN)"
  echo -e "  ${BRIGHT_CYAN}2.${NC} Open your VPN client application"
  echo -e "  ${BRIGHT_CYAN}3.${NC} Scan the QR code or paste the link"
  echo -e "  ${BRIGHT_CYAN}4.${NC} Select and connect to the server"
  echo ""
  echo -e "${DIM}For more information, visit your VPN client's documentation.${NC}"
}

while true; do

# -------- Preset Selection --------
if [ "${INTERACTIVE}" = true ] && [ -z "${PRESET:-}" ]; then
  print_section "Quick Start with Presets"
  echo ""
  echo -e "  ${BOLD}${BRIGHT_GREEN}1${NC} ${BRIGHT_GREEN}production${NC}       ${DIM}2048MB RAM, 1 CPU, 16 instances (High Performance)${NC}"
  echo -e "  ${BOLD}${BRIGHT_RED}2${NC} ${BRIGHT_RED}trojan-ws${NC}          ${DIM}TROJAN Protocol, yt3.ggpht.com (Optimized)${NC}"
  echo -e "  ${BOLD}${BRIGHT_CYAN}3${NC} ${BRIGHT_CYAN}vless-ws${NC}           ${DIM}VLESS Protocol, yt3.ggpht.com (Fast)${NC}"
  echo -e "  ${BOLD}${BRIGHT_YELLOW}4${NC} ${BRIGHT_YELLOW}vmess-ws${NC}           ${DIM}VMESS Protocol, yt3.ggpht.com (Compatible)${NC}"
  echo -e "  ${BOLD}${BRIGHT_MAGENTA}5${NC} ${BRIGHT_MAGENTA}custom${NC}            ${DIM}Configure everything manually${NC}"
  echo -e "  ${BOLD}${BRIGHT_WHITE}6${NC} ${BRIGHT_WHITE}exit${NC}              ${DIM}Exit script${NC}"
  echo ""

  read -rp "$(echo -e "${BOLD}${BRIGHT_BLUE}Select preset [1-6]${NC} ${DIM}(default: 1)${NC}: ")" PRESET_CHOICE
fi

PRESET_CHOICE="${PRESET_CHOICE:-1}"

case "$PRESET_CHOICE" in
  1)
    apply_preset "production"
    PRESET_MODE="production"
    print_success "Production preset (High Performance)"
    ;;
  2)
    apply_preset "trojan-ws"
    PRESET_MODE="trojan-ws"
    print_success "TROJAN Protocol preset"
    ;;
  3)
    apply_preset "vless-ws"
    PRESET_MODE="vless-ws"
    print_success "VLESS Protocol preset"
    ;;
  4)
    apply_preset "vmess-ws"
    PRESET_MODE="vmess-ws"
    print_success "VMESS Protocol preset"
    ;;
  5)
    PRESET_MODE="custom"
    print_success "Custom configuration mode"
    ;;
  6)
    echo -e "${BRIGHT_RED}Exiting script...${NC}"
    exit 0
    ;;
  *)
    echo -e "${BRIGHT_RED}Invalid option${NC}"
    exit 1
    ;;
esac

# -------- Telegram Bot --------
if [ "${INTERACTIVE}" = true ] && [ -z "${BOT_TOKEN:-}" ]; then
  print_section "Telegram Bot (Optional)"
  read -rp "$(echo -e "${BOLD}🤖 Bot Token${NC}") (press Enter to skip): " BOT_TOKEN
fi
BOT_TOKEN="${BOT_TOKEN:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CHAT_ID:-}" ] && [ -n "${BOT_TOKEN}" ]; then
  read -rp "$(echo -e "${BOLD}💬 Chat ID${NC}") (optional): " CHAT_ID
fi
CHAT_ID="${CHAT_ID:-}"

# -------- Region Name Mapping for Telegram --------
declare -A REGION_NAMES=(
  [us-central1]="US_🇺🇸"
  [us-east1]="US_e1_🇺🇸"
  [us-east4]="US_e4_🇺🇸"
  [us-east5]="US_e5_🇺🇸"
  [us-west1]="US_w1_🇺🇸"
  [us-west2]="US_w2_🇺🇸"
  [us-west3]="US_w3_🇺🇸"
  [us-west4]="US_w4_🇺🇸"
  [us-south1]="US_s1_🇺🇸"
  [northamerica-northeast1]="Canada1_🇨🇦"
  [northamerica-northeast2]="Canada2_🇨🇦"
  [southamerica-east1]="Brazil_🇧🇷"
  [europe-north1]="Finland_🇫🇮"
  [europe-central2]="Poland_🇵🇱"
  [europe-southwest1]="Spain_🇪🇸"
  [europe-west1]="Belgium_🇧🇪"
  [europe-west2]="UK_🇬🇧"
  [europe-west4]="Netherlands_🇳🇱"
  [europe-west6]="Switzerland_🇨🇭"
  [europe-west8]="Italy_🇮🇹"
  [europe-west9]="France_🇫🇷"
  [europe-west10]="Germany_🇩🇪"
  [europe-west12]="Austria_🇦🇹"
  [asia-east1]="Taiwan_🇹🇼"
  [asia-east2]="Hong_Kong_🇭🇰"
  [asia-northeast1]="Japan1_🇯🇵"
  [asia-northeast2]="Japan2_🇯🇵"
  [asia-northeast3]="South_Korea_🇰🇷"
  [asia-southeast1]="Singapore_🇸🇬"
  [asia-south1]="India_🇮🇳"
  [australia-southeast1]="Australia_🇦🇺"
  [africa-south1]="South_Africa_🇿🇦"
  [me-west1]="Israel_🇮🇱"
)
get_region_name() {
  local region_code=$1
  if [[ -v REGION_NAMES[$region_code] ]]; then
    echo "${REGION_NAMES[$region_code]}"
  else
    echo "$region_code"
  fi
}

# Telegram send function
send_telegram() {
  if [ -z "${BOT_TOKEN}" ] || [ -z "${CHAT_ID}" ]; then
    return 0
  fi

  build_telegram_message() {
    local body="$1"
    local ts_plus7
    local ts_plus1
    ts_plus7=$(date -d "@$((SESSION_START_TIME + 25000))" "+%Y-%m-%d %H:%M")
    ts_plus1=$(date -d "@$((SESSION_START_TIME + 3400))" "+%Y-%m-%d %H:%M")
    local speed_text
    if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
      local mbps
      mbps=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
      speed_text="${SPEED_LIMIT} KB/s (~${mbps} Mbps)"
    else
      speed_text="${SPEED_LIMIT}"
    fi
    
    # Get Service IP by resolving the Host domain
    local service_ip="unknown"
    if command -v nslookup >/dev/null 2>&1; then
      service_ip=$(nslookup "$HOST" 2>/dev/null | grep -A 1 "Name:" | grep "Address:" | awk '{print $2}' | head -1 || echo "unknown")
    elif command -v dig >/dev/null 2>&1; then
      service_ip=$(dig +short "$HOST" | head -1 || echo "unknown")
    fi
    [ -z "$service_ip" ] && service_ip="unknown"
    
    # Use Region as location reference (since Region is authoritative for Cloud Run)
    local service_region="$(get_region_name "${REGION}")"

    local msg="<b>📌 XRAY Deployment</b>
    "
    
    msg+="<b>Date (UTC+1):</b> ${ts_plus1}
    "
    msg+="<b>Date 6 Hours later:</b> ${ts_plus7}
   
    "
    msg+="<b>Service:</b> ${SERVICE}
    "
    msg+="<b>Protocol:</b> ${PROTO^^}
    "
    msg+="<b>Region:</b> ${service_region}
    "
    msg+="<b>Host:</b> ${HOST}
    "
    msg+="<b>Service IP:</b> ${service_ip}
    "
    msg+="<b>Network:</b> ${NETWORK_DISPLAY}
    "
   # msg+="<b>Speed Limit:</b> ${speed_text}
   # "
    msg+="${body}"
    echo "$msg"
  }

  local raw="$1"
  local message
  message=$(build_telegram_message "$raw")
  # URL encode the message properly and send as HTML
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${message}" \
    -d "parse_mode=HTML" \
    > /dev/null 2>&1
}

# Optional: install Telegram bot listener on this host (copies scripts, installs jq, systemd service)
install_telegram_bot() {
  # helper to run as root
  run_as_root() {
    if [ "$(id -u)" -ne 0 ]; then
      sudo bash -c "$*"
    else
      bash -c "$*"
    fi
  }

  echo "🔧 Installing Telegram bot listener..."

  # Copy scripts
  run_as_root "install -d /usr/local/bin && cp -v \"${PWD}/scripts/status.sh\" \"${PWD}/scripts/bot_listener.sh\" /usr/local/bin/"
  run_as_root "chmod +x /usr/local/bin/status.sh /usr/local/bin/bot_listener.sh"

  # Create environment file (safe permissions)
  echo "Writing /etc/default/yuyu_bot (permissions 600)..."
  # if user wants a restart command, ask interactively
  SERVICE_RESTART_CMD_VAL=""
  if [ "${INTERACTIVE}" = true ]; then
    read -rp "Optional: command to restart your service on 'restart' (e.g. systemctl restart xray) (press Enter to skip): " SERVICE_RESTART_CMD_VAL
  fi

  # Optional: allow forcing the listener process name (e.g. xray, nginx) for connection counting
  LISTENER_PROCESS_VAL=""
  if [ "${INTERACTIVE}" = true ]; then
    read -rp "Optional: listener process name to filter connections (e.g. xray, nginx) (press Enter to skip): " LISTENER_PROCESS_VAL
  fi

  # Create the file using sudo tee to preserve root ownership
  run_as_root "cat > /etc/default/yuyu_bot <<'EOF'
BOT_TOKEN=\"${BOT_TOKEN}\"
CHAT_ID=\"${CHAT_ID}\"
SERVICE_RESTART_CMD=\"${SERVICE_RESTART_CMD_VAL}\"
# Optional controls:
# ALLOW_REBOOT=yes to allow reboot command
# POLL_INTERVAL=60 to change polling interval (seconds)
# LISTENER_PROCESS=name  # if set, bot scripts will filter connections by this process name
LISTENER_PROCESS=\"${LISTENER_PROCESS_VAL}\"
EOF"
  run_as_root "chmod 600 /etc/default/yuyu_bot"

  # Ensure jq is installed
  if ! command -v jq >/dev/null 2>&1; then
    echo "Installing jq..."
    if command -v apt-get >/dev/null 2>&1; then
      run_as_root "apt-get update && apt-get install -y jq"
    elif command -v yum >/dev/null 2>&1; then
      run_as_root "yum install -y epel-release && yum install -y jq"
    elif command -v apk >/dev/null 2>&1; then
      run_as_root "apk add --no-cache jq"
    else
      echo "Could not detect package manager. Please install 'jq' manually."
    fi
  fi

  # Install systemd service if possible
  run_as_root "cp -v \"${PWD}/systemd/bot-listener.service\" /etc/systemd/system/bot-listener.service || true"

  if command -v systemctl >/dev/null 2>&1 && [ "$(ps -o comm=1)" = "systemd" ]; then
    echo "Enabling and starting systemd service..."
    run_as_root "systemctl daemon-reload || true"
    if run_as_root "systemctl enable --now bot-listener.service"; then
      echo "Service enabled and started: systemctl status bot-listener.service"
    else
      echo "Failed to start service via systemctl. You may need to start it manually later."
    fi
  else
    echo "Note: systemd not available on this host (or not PID 1). Service file installed but not started."
    echo "Installing lightweight helper scripts for non-systemd environments (/usr/local/bin/run_bot_nohup.sh and /usr/local/bin/stop_bot_nohup.sh)"
    run_as_root "cp -v \"${PWD}/scripts/run_bot_nohup.sh\" /usr/local/bin/ || true"
    run_as_root "cp -v \"${PWD}/scripts/stop_bot_nohup.sh\" /usr/local/bin/ || true"
    run_as_root "chmod +x /usr/local/bin/run_bot_nohup.sh /usr/local/bin/stop_bot_nohup.sh || true"
    run_as_root "mkdir -p /var/log && touch /var/log/yuyu_bot.log && chown root:root /var/log/yuyu_bot.log || true"

    if [ "${INTERACTIVE}" = true ]; then
      read -rp "Do you want to start the bot now in background via nohup? [y/N]: " START_NOHUP
    else
      START_NOHUP="n"
    fi

    if [[ "${START_NOHUP,,}" = "y" ]]; then
      echo "Starting bot via /usr/local/bin/run_bot_nohup.sh (logs -> /var/log/yuyu_bot.log)"
      run_as_root "BOT_TOKEN=\"${BOT_TOKEN}\" CHAT_ID=\"${CHAT_ID}\" /usr/local/bin/run_bot_nohup.sh"
      echo "Started via nohup; stop: sudo /usr/local/bin/stop_bot_nohup.sh"
      echo "To enable auto-start at boot (if supported) you can add to root crontab: @reboot /usr/local/bin/run_bot_nohup.sh"
    else
      echo "To start later (manual):"
      echo "  sudo BOT_TOKEN=\"<BOT_TOKEN>\" CHAT_ID=\"<CHAT_ID>\" /usr/local/bin/run_bot_nohup.sh"
      echo "To stop: sudo /usr/local/bin/stop_bot_nohup.sh"
      echo "To start at boot (crontab): sudo crontab -l | { cat; echo \"@reboot /usr/local/bin/run_bot_nohup.sh\"; } | sudo crontab -"
    fi
  fi
  # If user provided a listener override, print an informative message
  if [ -n "${LISTENER_PROCESS_VAL:-}" ]; then
    echo "Listener process override set (LISTENER_PROCESS): ${LISTENER_PROCESS_VAL}"
    echo "To change it later, edit /etc/default/yuyu_bot and restart the bot listener (systemctl restart bot-listener.service or restart the nohup process)."
  fi
  echo "Installation finished. Logs: sudo journalctl -u bot-listener.service -f (if systemd available) or tail -f /var/log/yuyu_bot.log"
}

# If user provided BOT_TOKEN and CHAT_ID during interactive install, ask to install bot listener
# Only ask if custom preset is selected (not for quick presets)
if [ "$PRESET_MODE" = "custom" ] && [ -n "${BOT_TOKEN:-}" ] && [ -n "${CHAT_ID:-}" ]; then
  if [ "${INTERACTIVE}" = true ]; then
    read -rp "Do you want to install Telegram bot listener on this host now? [y/N]: " INSTALL_BOT_ANSWER
  else
    INSTALL_BOT_ANSWER="n"
  fi
  INSTALL_BOT_ANSWER="${INSTALL_BOT_ANSWER:-n}"
  if [[ "${INSTALL_BOT_ANSWER,,}" = "y" ]]; then
    install_telegram_bot
  fi
fi

# -------- Protocol --------
# Handle protocol selection with preset support
if [ "${INTERACTIVE}" = true ] && [ -z "${PROTO_CHOICE:-}" ]; then
  if [ -z "${PRESET_PROTO:-}" ]; then
    # Interactive selection - show menu
    print_section "Choose Protocol"
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}1${NC} ${BRIGHT_CYAN}VLESS${NC}       ${DIM}Fast, modern, lightweight${NC}"
    echo -e "  ${BOLD}${BRIGHT_YELLOW}2${NC} ${BRIGHT_YELLOW}VMESS${NC}       ${DIM}Compatible, widely supported${NC}"
    echo -e "  ${BOLD}${BRIGHT_RED}3${NC} ${BRIGHT_RED}TROJAN${NC}      ${DIM}Camouflages as HTTPS server${NC}"
    echo ""
    read -rp "$(echo -e "${BOLD}${BRIGHT_BLUE}Select protocol [1-3]${NC} ${DIM}(default: 1)${NC}: ")" PROTO_CHOICE
  else
    PROTO="$PRESET_PROTO"
    print_success "Using preset protocol: $PROTO"
  fi
fi

# Process the protocol choice
PROTO_CHOICE="${PROTO_CHOICE:-1}"
case "$PROTO_CHOICE" in
  1)
    PROTO="vless"
    print_success "VLESS protocol selected"
    ;;
  2)
    PROTO="vmess"
    print_success "VMESS protocol selected"
    ;;
  3)
    PROTO="trojan"
    print_success "TROJAN protocol selected"
    ;;
  *)
    print_error "Invalid protocol selection"
    exit 1
    ;;
esac

# -------- Network Type --------
# Cloud Run supports WebSocket (ws) reliably; gRPC has compatibility issues
NETWORK="ws"
NETWORK_DISPLAY="WebSocket"

# -------- WebSocket Path --------
if [ "${INTERACTIVE}" = true ] && [ -z "${WSPATH:-}" ]; then
  # Use preset path if available, otherwise ask
  if [ -z "${PRESET_WSPATH:-}" ]; then
    read -rp "$(echo -e "${BOLD}📡 WebSocket Path${NC} (default: /ws): ")
 " WSPATH
  else
    WSPATH="${PRESET_WSPATH}"
    print_info "WebSocket Path (from preset): $WSPATH"
  fi
fi
WSPATH="${WSPATH:-${PRESET_WSPATH:-/ws}}"

# Custom hostname is not supported reliably by this script; always use Cloud Run default
CUSTOM_HOST=""

# -------- Service Name --------
if [ "${INTERACTIVE}" = true ] && [ -z "${SERVICE:-}" ]; then
  # Use preset service if available, otherwise ask
  if [ -z "${PRESET_SERVICE:-}" ]; then
    read -rp "$(echo -e "${BOLD}🪪 Cloud Run Service Name${NC} (default: xray-ws): ")
 " SERVICE
  else
    SERVICE="${PRESET_SERVICE}"
    print_info "Cloud Run Service Name (from preset): $SERVICE"
  fi
fi
SERVICE="${SERVICE:-${PRESET_SERVICE:-xray-ws}}"

# Validate service name format
if ! [[ "$SERVICE" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
  print_error "Invalid service name. Use lowercase alphanumeric and hyphens only (1-63 chars)."
  exit 1
fi
print_success "Service name: $SERVICE"

# -------- Optional Link Parameters --------
if [ "${INTERACTIVE}" = true ] && [ -z "${SNI_CHOICE:-}" ]; then
  # Use preset SNI if available, otherwise ask
  if [ -z "${PRESET_SNI:-}" ]; then
    print_section "Advanced Settings (Optional)"
    echo ""
    echo -e "  ${BOLD}1${NC} yt3.ggpht.com    (YouTube CDN - Recommended)"
    echo -e "  ${BOLD}2${NC} www.google.com   (Google CDN)"
    echo -e "  ${BOLD}3${NC} youtube.com  (YouTube Direct)"
    echo -e "  ${BOLD}4${NC} ${GRAY}(Leave blank)${NC}     No SNI"
    echo ""
    read -rp "$(echo -e "${BOLD}Select SNI [1-4]${NC} (default: 4): ")
 " SNI_CHOICE
  else
    SNI_CHOICE="5"  # Use value that skips to preset
  fi
fi
SNI_CHOICE="${SNI_CHOICE:-4}"

case "$SNI_CHOICE" in
  1)
    SNI="yt3.ggpht.com"
    print_success "SNI: $SNI"
    ;;
  2)
    SNI="www.google.com"
    print_success "SNI: $SNI"
    ;;
  3)
    SNI="m.youtube.com"
    print_success "SNI: $SNI"
    ;;
  4)
    SNI=""
    print_info "No SNI selected"
    ;;
  5)
    SNI="${PRESET_SNI}"  # Use preset SNI
    [ -n "$SNI" ] && print_success "SNI (preset): $SNI" || print_info "No SNI (preset)"
    ;;
  *)
    SNI="$SNI_CHOICE"
    print_success "Custom SNI: $SNI"
    ;;
esac

# -------- ALPN --------
if [ "${INTERACTIVE}" = true ] && [ -z "${ALPN:-}" ]; then
  # Use preset ALPN if available, otherwise ask
  if [ -z "${PRESET_ALPN:-}" ]; then
    echo ""
    echo -e "  ${BOLD}1${NC} default          (h2, http/1.1)"
    echo -e "  ${BOLD}2${NC} h2,http/1.1      (HTTP/2 Priority)"
    echo -e "  ${BOLD}3${NC} h2               (HTTP/2 Only)"
    echo -e "  ${BOLD}4${NC} http/1.1         (HTTP/1.1 Only)"
    echo ""
    read -rp "$(echo -e "${BOLD}Select ALPN [1-4]${NC} (default: 1): ")
 " ALPN_CHOICE
  else
    ALPN_CHOICE="5"  # Use value that skips to preset
  fi
fi
ALPN_CHOICE="${ALPN_CHOICE:-1}"

case "$ALPN_CHOICE" in
  1)
    ALPN="default"
    print_success "ALPN: default"
    ;;
  2)
    ALPN="h2,http/1.1"
    print_success "ALPN: h2,http/1.1"
    ;;
  3)
    ALPN="h2"
    print_success "ALPN: h2"
    ;;
  4)
    ALPN="http/1.1"
    print_success "ALPN: http/1.1"
    ;;
  5)
    ALPN="${PRESET_ALPN}"  # Use preset ALPN
    print_success "ALPN (preset): $ALPN"
    ;;
  *)
    print_error "Invalid ALPN selection"
    exit 1
    ;;
esac

# Use region name as the default identifier for links
# CUSTOM_ID is set after region selection to the chosen region
CUSTOM_ID=""

# -------- UUID --------
UUID=$(cat /proc/sys/kernel/random/uuid)

# -------- Detect Available Cloud Run Regions --------
# Safe dry-run region check with results caching
# This implementation uses parallel checks and stores results in a cache file

CACHE_FILE="region_scan_results.txt"
CANDIDATE_REGIONS=("us-central1" "us-east1" "us-east4" "us-west1" "europe-west1" "europe-west4")

# Timeout for deploy checks (used with `timeout`). Can be overridden by env var DEPLOY_CHECK_TIMEOUT
DEPLOY_CHECK_TIMEOUT="${DEPLOY_CHECK_TIMEOUT:-60s}"

# خريطة الرموز إلى الدولة / المنطقة
declare -A REGION_COUNTRY_MAP=(
  ["us-central1"]="United States - Iowa"
  ["us-east1"]="United States - South Carolina"
  ["us-east4"]="United States - Northern Virginia"
  ["us-west1"]="United States - Oregon"
  ["europe-west1"]="Belgium"
  ["europe-west4"]="Netherlands"
)

# Advanced region check using org-policies (faster method)
check_region_via_org_policy() {
  local cache_file=$1
  
  # Get current project
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
  if [ -z "$PROJECT_ID" ]; then
    print_warning "Cannot get project ID. Falling back to legacy method."
    return 1
  fi
  
  print_info "Attempting to fetch allowed regions via org-policies (faster method)..."
  
  # Attempt to describe org-policies for resource locations
  # (orgpolicy API should already be enabled by enable_required_apis function)
  OUTPUT=$(gcloud org-policies describe constraints/gcp.resourceLocations --project="$PROJECT_ID" --format=yaml 2>&1)
  
  # Check if the command failed
  if echo "$OUTPUT" | grep -qE "(ERROR|error|not found|No API)"; then
    print_warning "Org-policy constraints not available. Using legacy method."
    return 1
  fi
  
  # If we have output with allowedValues, parse it
  if echo "$OUTPUT" | grep -q "allowedValues"; then
    print_success "Org-policy data retrieved. Parsing allowed regions..."
    
    # Extract regions from the output
    # Looking for entries like "in:us-central1-locations" or similar
    REGIONS=$(echo "$OUTPUT" | grep -oP "in:[a-z0-9\-]+\-locations" | sed 's/in://g' | sed 's/-locations//g' | grep -vE '^(aws|azure)$' | sort | uniq)
    
    if [ -n "$REGIONS" ]; then
      # Store results in cache
      while IFS= read -r region; do
        if [ -n "$region" ]; then
          echo "[${region}] ALLOWED (via org-policy)" >> "$cache_file"
        fi
      done <<< "$REGIONS"
      
      print_success "Successfully parsed regions from org-policies"
      return 0
    fi
  fi
  
  print_warning "No allowed values found in org-policy. Using legacy method."
  return 1
}

# Parallel region check function (safe dry-run - legacy method)
check_region_safe() {
  local region=$1
  local cache_file=$2
  
  # Delete previous test service to avoid conflicts
  gcloud run services delete test-check-${region} --region=${region} --quiet 2>/dev/null || true

  # Deploy test service with minimal config and delete it immediately
  # Use a timeout to keep checks fast and avoid long builds
  OUTPUT=$(timeout ${DEPLOY_CHECK_TIMEOUT} gcloud run deploy test-check-${region} \
    --image=us-docker.pkg.dev/cloudrun/container/hello \
    --region="${region}" \
    --allow-unauthenticated \
    --quiet 2>&1 || true)

  # Check result
  if echo "$OUTPUT" | grep -q "constraints/gcp.resourceLocations"; then
    echo "[${region}] BLOCKED (Org Policy)"
    echo "[${region}] BLOCKED" >> "$cache_file"
  elif echo "$OUTPUT" | grep -q "Validating configuration...failed"; then
    # Faster detection of validation failures before full build
    echo "[${region}] BLOCKED (Validation Failed)"
    echo "[${region}] BLOCKED" >> "$cache_file"
  elif echo "$OUTPUT" | grep -q "Validating configuration...done\\|Setting IAM Policy\\|Service\\|https://"; then
    # Consider deployment allowed as soon as validation completes (speeds up detection)
    echo "[${region}] ALLOWED"
    # Delete test service immediately
    gcloud run services delete test-check-${region} --region=${region} --quiet 2>/dev/null || true
    echo "[${region}] ALLOWED" >> "$cache_file"
  else
    echo "[${region}] UNKNOWN"
    echo "[${region}] UNKNOWN" >> "$cache_file"
  fi
}

detect_available_regions() {
  print_info "🔍 Scanning Cloud Run region availability..."
  echo ""
  
  # Check if gcloud is installed and user is authenticated
  if ! command -v gcloud >/dev/null 2>&1; then
    print_warning "gcloud CLI not found. Using REGION_COUNTRY_MAP as default regions."
    for r in "${!REGION_COUNTRY_MAP[@]}"; do
      echo "__REGION:__$r"
    done
    return 0
  fi
  # Fast path: get regions that Cloud Run supports in this account/location
  GCLOUD_REGIONS=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)

  # Check if cache file exists and is recent (less than 24 hours old)
  if [ -f "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ]; then
    local file_age=$((($(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || stat -c%Y "$CACHE_FILE" 2>/dev/null || echo 0))))
    if [ $file_age -lt 86400 ]; then
      print_info "Using cached region results (age: $(($file_age/3600))h)"
      # Read cached results with error handling using mapfile
      if grep -q "✅ ALLOWED" "$CACHE_FILE" 2>/dev/null; then
        mapfile -t cached_regions < <(grep "✅ ALLOWED" "$CACHE_FILE" 2>/dev/null | sed 's/\[\(.*\)\].*/\1/' | sort -u)
        if [ ${#cached_regions[@]} -gt 0 ]; then
          for region in "${cached_regions[@]}"; do
            [ -n "$region" ] && echo "__REGION:__$region"
          done
          return 0
        fi
      fi
    fi
  fi
  
  # Perform fresh scan - Try org-policy method first (faster)
  print_info "Attempting fast org-policy based region detection..."
  echo ""
  
  # Clear cache file
  > "$CACHE_FILE"
  
  # Try the advanced org-policy method first
  if check_region_via_org_policy "$CACHE_FILE"; then
    print_success "Successfully retrieved regions via org-policy (fast method)"
    echo ""
    # Parse and display results from cache
    if grep -q "ALLOWED" "$CACHE_FILE" 2>/dev/null; then
      echo "Available Cloud Run regions (from org-policy):"
      mapfile -t regions_list < <(grep "ALLOWED" "$CACHE_FILE" 2>/dev/null | sed 's/\[\(.*\)\].*/\1/' | sort -u)
      for region in "${regions_list[@]}"; do
        if [ -n "$region" ]; then
          echo "__REGION:__$region"
        fi
      done
      return 0
    fi
  fi
  
  # Fallback to legacy region scan if org-policy method failed
  print_warning "Org-policy method unavailable or failed. Falling back to legacy scan method..."
  print_info "Running legacy region scan in parallel (this may take 1-2 minutes)..."
  echo ""
  
  # Clear cache file for fresh legacy scan
  > "$CACHE_FILE"
  # Decide which regions to check: intersect candidate list with gcloud-reported regions
  to_check=()
  if [ -n "$GCLOUD_REGIONS" ]; then
    for region in "${CANDIDATE_REGIONS[@]}"; do
      if echo "$GCLOUD_REGIONS" | grep -xq "$region"; then
        to_check+=("$region")
      fi
    done
  fi

  # If intersection is empty, fall back to candidate list (best-effort)
  if [ ${#to_check[@]} -eq 0 ]; then
    to_check=("${CANDIDATE_REGIONS[@]}")
  fi

  # Run checks in parallel (with timeout inside check_region_safe)
  for region in "${to_check[@]}"; do
    check_region_safe "$region" "$CACHE_FILE" &
  done
  wait
  
  # Ensure all data is written to disk
  sync 2>/dev/null || true
  sleep 2
  
  echo ""
  print_success "Region scan completed. Results saved to $CACHE_FILE"
  echo ""
  
  # Print and return allowed regions
  local allowed_count=0
  if [ -f "$CACHE_FILE" ] && [ -r "$CACHE_FILE" ] && grep -q "ALLOWED" "$CACHE_FILE" 2>/dev/null; then
    echo "Available Cloud Run regions:"
    # Use a temporary array to collect regions reliably
    mapfile -t regions_list < <(grep "ALLOWED" "$CACHE_FILE" 2>/dev/null | sed 's/\[\(.*\)\].*/\1/' | sort -u)
    for region in "${regions_list[@]}"; do
      if [ -n "$region" ]; then
        region_name="$(get_region_name "$region")"
        echo "  - $region ($region_name)"
        echo "__REGION:__$region"
        ((allowed_count++))
      fi
    done
    
    if [ $allowed_count -eq 0 ]; then
      print_warning "No valid regions found in cache file. Using fallback regions."
      for r in "${!REGION_COUNTRY_MAP[@]}"; do
        echo "__REGION:__$r"
      done
    fi
  else
    print_warning "No regions detected as allowed or cache file not readable. Using fallback regions."
    for r in "${!REGION_COUNTRY_MAP[@]}"; do
      echo "__REGION:__$r"
    done
  fi
}

# Get available regions once
print_section "Detecting Available Cloud Run Regions"
echo ""
print_info "Please wait - testing region availability in parallel (may take a minute or two)"
echo ""

# Extract regions from output safely
FULL_OUTPUT=$(detect_available_regions)
mapfile -t AVAILABLE_REGIONS_ARRAY < <(echo "$FULL_OUTPUT" | grep "^__REGION:__" | sed 's/^__REGION:__//')

# Convert array to newline-separated string for easier filtering
AVAILABLE_REGIONS=$(printf '%s\n' "${AVAILABLE_REGIONS_ARRAY[@]}")

# Ensure we have regions available; if empty, use fallback
if [ -z "$AVAILABLE_REGIONS" ] || [ ${#AVAILABLE_REGIONS_ARRAY[@]} -eq 0 ]; then
  print_warning "No regions were detected. Using fallback regions from REGION_COUNTRY_MAP."
  mapfile -t AVAILABLE_REGIONS_ARRAY < <(printf '%s\n' "${!REGION_COUNTRY_MAP[@]}")
  AVAILABLE_REGIONS=$(printf '%s\n' "${AVAILABLE_REGIONS_ARRAY[@]}")
fi

# Create arrays of available regions for easier filtering
FILTERED_SUGGESTED=()
for r in "${SUGGESTED_REGIONS[@]}"; do
  if echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
    FILTERED_SUGGESTED+=("$r")
  fi
done

FILTERED_MORE=()
for r in "${MORE_REGIONS[@]}"; do
  if echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
    FILTERED_MORE+=("$r")
  fi
done

# If no suggested regions are available, use available regions as fallback
if [ ${#FILTERED_SUGGESTED[@]} -eq 0 ]; then
  mapfile -t FILTERED_SUGGESTED < <(printf '%s\n' "${AVAILABLE_REGIONS_ARRAY[@]}" | head -5)
fi

# Brief pause to let user see the completion message
sleep 1

# -------- Region Select --------
print_section "Select Cloud Run Region"

if [[ "$PRESET_MODE" =~ ^(trojan-ws|vless-ws|vmess-ws)$ ]]; then
  if [ ${#FILTERED_SUGGESTED[@]} -eq 1 ]; then
    REGION="${FILTERED_SUGGESTED[0]}"
    CUSTOM_ID="$REGION"
    print_success "Auto-selected region: $REGION"
    deploy_service
    continue
  elif [ ${#FILTERED_SUGGESTED[@]} -eq 2 ]; then
    for region in "${FILTERED_SUGGESTED[@]}"; do
      REGION="$region"
      CUSTOM_ID="$REGION"
      print_success "Deploying for region: $REGION"
      deploy_service
    done
    continue
  fi
fi

if [ "${INTERACTIVE}" = true ] && [ -z "${REGION:-}" ]; then
  SELECTED_REGION=""
  while [ -z "${SELECTED_REGION}" ]; do
    i=0  # Reset counter at start of each loop iteration
    echo ""
    
    # Show available suggested regions only
    if [ ${#FILTERED_SUGGESTED[@]} -gt 0 ]; then
      echo -e "${BOLD}🌍 Available Suggested Regions:${NC}"
      echo ""
      i=1
      for r in "${FILTERED_SUGGESTED[@]}"; do
        region_name="$(get_region_name "$r")"
        printf "  ${BOLD}%2d${NC} ${GREEN}✓${NC} %s (%s)\n" "$i" "$r" "$region_name"
        ((i++))
      done
      echo ""
    else
      echo -e "${YELLOW}⚠ No suggested regions available${NC}"
      echo ""
    fi
    
    # Show "more regions" option
    next_idx=$((i))
    printf "  ${BOLD}%2d${NC} ${CYAN}📋 Show more regions${NC}\n" "$next_idx"
    echo ""
    read -rp "$(echo -e "${BOLD}Select region${NC} [1-$next_idx]: ")" REGION_IDX
    REGION_IDX="${REGION_IDX:-1}"
    
    if [[ ! "$REGION_IDX" =~ ^[0-9]+$ ]] || [ "$REGION_IDX" -lt 1 ] || [ "$REGION_IDX" -gt $next_idx ]; then
      print_error "Invalid region selection. Please try again."
      continue
    fi
    
    # Check if user selected "more"
    if [ "$REGION_IDX" -eq $next_idx ]; then
      echo ""
      echo -e "${BOLD}🌍 More Available Regions:${NC}"
      echo ""
      
      # Show SUGGESTED_REGIONS first (for quick access)
      if [ ${#FILTERED_SUGGESTED[@]} -gt 0 ]; then
        echo -e "${GREEN}✓ Suggested (quick access):${NC}"
        for i_idx in "${!FILTERED_SUGGESTED[@]}"; do
          r="${FILTERED_SUGGESTED[$i_idx]}"
          region_name="$(get_region_name "$r")"
          printf "  %2d ✓ %s (%s)\n" "$((i_idx + 1))" "$r" "$region_name"
        done
        echo ""
      fi
      
      # Then, display FILTERED_MORE (available tested)
      if [ ${#FILTERED_MORE[@]} -gt 0 ]; then
        echo -e "${GREEN}✓ Available (tested):${NC}"
        for i_idx in "${!FILTERED_MORE[@]}"; do
          r="${FILTERED_MORE[$i_idx]}"
          region_name="$(get_region_name "$r")"
          printf "  %2d ✓ %s (%s)\n" "$((${#FILTERED_SUGGESTED[@]} + i_idx + 1))" "$r" "$region_name"
        done
        echo ""
      fi
      
      # Then, display untested regions from MORE_REGIONS
      echo -e "${CYAN}? Untested regions (may be available):${NC}"
      untested_idx=$((${#FILTERED_SUGGESTED[@]} + ${#FILTERED_MORE[@]}))
      
      untested_count=0
      for r in "${MORE_REGIONS[@]}"; do
        if ! echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
          untested_count=$((untested_count + 1))
          printf "  %2d ? %s\n" "$((untested_idx + untested_count))" "$r"
        fi
      done
      
      if [ $untested_count -eq 0 ] && [ ${#FILTERED_MORE[@]} -eq 0 ] && [ ${#FILTERED_SUGGESTED[@]} -eq 0 ]; then
        print_error "❌ No additional regions available"
        continue
      fi
      
      echo ""
      max_more_idx=$((${#FILTERED_SUGGESTED[@]} + ${#FILTERED_MORE[@]} + untested_count))
      read -rp "$(echo -e "${BOLD}Select region${NC} [1-$max_more_idx] (default: 1): ")" MORE_REGION_IDX
      MORE_REGION_IDX="${MORE_REGION_IDX:-1}"
      
      if [[ ! "$MORE_REGION_IDX" =~ ^[0-9]+$ ]] || [ "$MORE_REGION_IDX" -lt 1 ] || [ "$MORE_REGION_IDX" -gt $max_more_idx ]; then
        print_error "Invalid region selection. Please try again."
        continue
      fi
      
      # Get the selected region
      if [ "$MORE_REGION_IDX" -le ${#FILTERED_SUGGESTED[@]} ]; then
        # Selected from FILTERED_SUGGESTED
        SELECTED_REGION="${FILTERED_SUGGESTED[$((MORE_REGION_IDX - 1))]}"
      elif [ "$MORE_REGION_IDX" -le $((${#FILTERED_SUGGESTED[@]} + ${#FILTERED_MORE[@]})) ]; then
        # Selected from FILTERED_MORE
        SELECTED_REGION="${FILTERED_MORE[$((MORE_REGION_IDX - ${#FILTERED_SUGGESTED[@]} - 1))]}"
      else
        # Selected from untested regions
        selected_untested_idx=$((MORE_REGION_IDX - ${#FILTERED_SUGGESTED[@]} - ${#FILTERED_MORE[@]} - 1))
        untested_count=0
        for r in "${MORE_REGIONS[@]}"; do
          if ! echo "$AVAILABLE_REGIONS" | grep -xq "$r"; then
            if [ $untested_count -eq $selected_untested_idx ]; then
              SELECTED_REGION="$r"
              break
            fi
            ((untested_count++))
          fi
        done
      fi
    else
      # Selected from suggested regions
      if [ $REGION_IDX -le ${#FILTERED_SUGGESTED[@]} ]; then
        SELECTED_REGION="${FILTERED_SUGGESTED[$((REGION_IDX-1))]}"
      else
        print_error "Invalid region selection."
        continue
      fi
    fi
  done
  
  REGION="$SELECTED_REGION"
  # set custom identifier to region name
  CUSTOM_ID="$REGION"
fi
REGION="${REGION:-us-central1}"
print_success "Selected region: $REGION"

# -------- Performance Settings --------
print_section "Performance Configuration"

if [ "$PRESET_MODE" = "custom" ]; then
  echo -e "${GRAY}(Optional - press Enter to skip each field)${NC}"
else
  echo -e "${GRAY}Preset: ${BOLD}$PRESET_MODE${GRAY} (press Enter to keep)${NC}"
fi

echo ""

if [ "${INTERACTIVE}" = true ] && [ -z "${MEMORY:-}" ]; then
  read -rp "$(echo -e "${BOLD}💾 Memory (MB)${NC} [512/1024/2048]: ")" MEMORY
fi
MEMORY="${MEMORY:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CPU:-}" ]; then
  read -rp "$(echo -e "${BOLD}⚙️  CPU cores${NC} [0.5/1/2]: ")" CPU
fi
CPU="${CPU:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${TIMEOUT:-}" ]; then
  read -rp "$(echo -e "${BOLD}⏱️  Timeout (seconds)${NC} [300/1800/3600]: ")" TIMEOUT
fi
TIMEOUT="${TIMEOUT:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${MAX_INSTANCES:-}" ]; then
  read -rp "$(echo -e "${BOLD}📊 Max instances${NC} [5/10/20/50]: ")" MAX_INSTANCES
fi
MAX_INSTANCES="${MAX_INSTANCES:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CONCURRENCY:-}" ]; then
  read -rp "$(echo -e "${BOLD}🔗 Max concurrent requests${NC} [100/500/1000]: ")" CONCURRENCY
fi
CONCURRENCY="${CONCURRENCY:-}"

# Speed Limit: قيمة ثابتة (لا تؤثر حالياً على السرعة الفعلية)
SPEED_LIMIT="${SPEED_LIMIT:-0}"

# Show what was selected
echo ""
print_section "Configuration Summary"
echo ""
[ -n "${MEMORY}" ] && print_success "Memory: ${BOLD}${MEMORY}${NC} MB" || print_info "Memory: (Cloud Run default)"
[ -n "${CPU}" ] && print_success "CPU: ${BOLD}${CPU}${NC} cores" || print_info "CPU: (Cloud Run default)"
[ -n "${TIMEOUT}" ] && print_success "Timeout: ${BOLD}${TIMEOUT}${NC}s" || print_info "Timeout: (Cloud Run default)"
[ -n "${MAX_INSTANCES}" ] && print_success "Max instances: ${BOLD}${MAX_INSTANCES}${NC}" || print_info "Max instances: (Cloud Run default)"
[ -n "${CONCURRENCY}" ] && print_success "Max concurrency: ${BOLD}${CONCURRENCY}${NC}" || print_info "Max concurrency: (Cloud Run default)"

# -------- Sanity checks --------
print_section "Validation"

if ! command -v gcloud >/dev/null 2>&1; then
  print_error "gcloud CLI not found. Install and authenticate first."
  exit 1
fi
print_success "gcloud CLI found"

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "${PROJECT:-}" ]; then
  print_error "No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
  exit 1
fi
print_success "GCP Project: $PROJECT"
print_success "All required APIs are enabled"

# -------- Deploying XRAY to Cloud Run --------
print_section "Deploying XRAY to Cloud Run"
echo ""

# Get PROJECT_NUMBER early (needed for HOST env var)
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project 2>/dev/null) --format="value(projectNumber)" 2>/dev/null)

# Build deploy command with optional parameters
DEPLOY_ARGS=(
  "--source" "."
  "--region" "$REGION"
  "--platform" "managed"
  "--allow-unauthenticated"
)

[ -n "${MEMORY}" ] && DEPLOY_ARGS+=("--memory" "${MEMORY}Mi")
[ -n "${CPU}" ] && DEPLOY_ARGS+=("--cpu" "${CPU}")
[ -n "${TIMEOUT}" ] && DEPLOY_ARGS+=("--timeout" "${TIMEOUT}")
[ -n "${MAX_INSTANCES}" ] && DEPLOY_ARGS+=("--max-instances" "${MAX_INSTANCES}")
DEPLOY_ARGS+=("--min-instances" "${MIN_INSTANCES:-4}")
[ -n "${EXEC_ENV}" ] && DEPLOY_ARGS+=("--execution-environment" "${EXEC_ENV}")
[ -n "${CONCURRENCY}" ] && DEPLOY_ARGS+=("--concurrency" "${CONCURRENCY}")

# Speed limit is now configured interactively or via environment variable

# Use Cloud Run service URL as WebSocket host header
# Format: service-projectnumber.region.run.app
DEPLOY_ARGS+=("--set-env-vars" "PROTO=${PROTO},USER_ID=${UUID},WS_PATH=${WSPATH},NETWORK=${NETWORK},SPEED_LIMIT=${SPEED_LIMIT},HOST=${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app")
DEPLOY_ARGS+=("--quiet")

# -------- Get URL --------
gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}"

# -------- Get URL and Host --------

# Use custom hostname if provided, otherwise use Cloud Run default
if [ -n "${CUSTOM_HOST}" ]; then
  HOST="${CUSTOM_HOST}"
  echo "Service URL: https://${HOST}"
  echo "✅ Using custom hostname: ${HOST}"
else
  HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
  echo "Service URL: https://${HOST}"
  echo "✅ Using Cloud Run default: ${HOST}"
fi

# -------- Get URL and Host --------

# Use custom hostname if provided, otherwise use Cloud Run default
if [ -n "${CUSTOM_HOST}" ]; then
  HOST="${CUSTOM_HOST}"
  echo "Service URL: https://${HOST}"
  print_success "Using custom hostname: ${HOST}"
else
  HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
  echo ""
  print_success "Service deployed successfully!"
  echo "Service URL: ${BOLD}https://${HOST}${NC}"
fi

# -------- Output --------
echo ""
echo -e "${BRIGHT_GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}              ✅ ${BRIGHT_WHITE}${BOLD}DEPLOYMENT SUCCESS${NC}               ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "  ${BRIGHT_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Protocol${NC}:       ${BRIGHT_GREEN}${PROTO^^}${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Address${NC}:       ${BRIGHT_CYAN}${HOST}${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Port${NC}:          ${BRIGHT_YELLOW}443${NC} ${DIM}(HTTPS)${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}UUID/PWD${NC}:      ${BRIGHT_MAGENTA}${UUID}${NC}"

if [ "$NETWORK" = "ws" ]; then
  echo -e "  ${BOLD}${BRIGHT_CYAN}Path${NC}:          ${BRIGHT_BLUE}${WSPATH}${NC}"
elif [ "$NETWORK" = "grpc" ]; then
  echo -e "  ${BOLD}${BRIGHT_CYAN}Service${NC}:       ${BRIGHT_BLUE}${WSPATH}${NC}"
fi

echo -e "  ${BOLD}${BRIGHT_CYAN}Network${NC}:       ${BRIGHT_CYAN}${NETWORK_DISPLAY}${NC}"
echo -e "  ${BOLD}${BRIGHT_CYAN}Security${NC}:      ${BRIGHT_GREEN}TLS${NC} ${DIM}(Enabled)${NC}"

if [[ "${SPEED_LIMIT}" =~ ^[0-9]+$ ]]; then
  MBPS=$(awk "BEGIN{printf \"%.2f\", (${SPEED_LIMIT}*8)/1000}")
  echo -e "  ${BOLD}${BRIGHT_CYAN}Speed Limit${NC}:   ${BRIGHT_YELLOW}${SPEED_LIMIT} KB/s${NC} ${DIM}(~${MBPS} Mbps)${NC}"
else
  echo -e "  ${BOLD}${BRIGHT_CYAN}Speed Limit${NC}:   ${BRIGHT_YELLOW}${SPEED_LIMIT}${NC}"
fi

if [ -n "${MEMORY}${CPU}${TIMEOUT}${MAX_INSTANCES}${CONCURRENCY}" ]; then
  echo ""
  echo -e "  ${BRIGHT_MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}${BRIGHT_BLUE}⚙️  Configuration Applied${NC}:"
  [ -n "${MEMORY}" ] && echo -e "      ${DIM}├─${NC} Memory:        ${BRIGHT_GREEN}${MEMORY}${NC} MB"
  [ -n "${CPU}" ] && echo -e "      ${DIM}├─${NC} CPU:           ${BRIGHT_GREEN}${CPU}${NC} cores"
  [ -n "${TIMEOUT}" ] && echo -e "      ${DIM}├─${NC} Timeout:       ${BRIGHT_GREEN}${TIMEOUT}${NC}s"
  [ -n "${MAX_INSTANCES}" ] && echo -e "      ${DIM}├─${NC} Max Instances: ${BRIGHT_GREEN}${MAX_INSTANCES}${NC}"
  [ -n "${CONCURRENCY}" ] && echo -e "      ${DIM}└─${NC} Concurrency:   ${BRIGHT_GREEN}${CONCURRENCY}${NC} req/instance"
fi

echo ""
echo -e "${BRIGHT_CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                              ${BRIGHT_CYAN}${BOLD}║${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}║${NC}              📎 ${BRIGHT_WHITE}${BOLD}SHARED LINKS${NC}                    ${BRIGHT_CYAN}${BOLD}║${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}║${NC}                                                              ${BRIGHT_CYAN}${BOLD}║${NC}"
echo -e "${BRIGHT_CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"

# -------- Build Query Parameters --------
# Build query parameters for WebSocket (only supported on Cloud Run)
QUERY_PARAMS="type=ws&security=tls&path=${WSPATH}"
if [ -n "${SNI}" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&sni=${SNI}"
fi
if [ -n "${ALPN}" ]; then
  QUERY_PARAMS="${QUERY_PARAMS}&alpn=${ALPN}"
fi
# Add host parameter for WebSocket compatibility
QUERY_PARAMS="${QUERY_PARAMS}&host=${HOST}"

# Build fragment with custom ID
LINK_FRAGMENT="xray"
if [ -n "${CUSTOM_ID}" ]; then
  LINK_FRAGMENT="(${CUSTOM_ID})"
fi

# -------- Generate Protocol Links --------
# Generate primary link using unified function
SHARE_LINK="$(build_protocol_link "$PROTO" "$HOST" "443" "$QUERY_PARAMS" "$LINK_FRAGMENT")"
print_protocol_link "$PROTO" "$SHARE_LINK"

# -------- Generate Alternative URL (short URL) --------
# Try to get the short URL from gcloud (if available)
ALT_HOST=$(gcloud run services describe "$SERVICE" --region "$REGION" --format="value(status.url)" 2>/dev/null | sed 's|https://||' | sed 's|/||g' || echo "")

if [ -z "$ALT_HOST" ]; then
  ALT_HOST="$HOST"  # fallback to primary if short URL not available
fi

# Generate alternative link with short URL only if different from primary
if [ "$ALT_HOST" != "$HOST" ]; then
  # use friendly region name for fragment (fallback to code if not known)
  friendly_region="$(get_region_name "$REGION")"
  # add "-alt" suffix when building alt fragments to indicate the short URL
  friendly_region_alt="${friendly_region}_SN"

  if [ "$PROTO" = "vless" ] || [ "$PROTO" = "trojan" ]; then
    alt_query=$(echo "$QUERY_PARAMS" | sed 's/&host=[^&]*//g')
    alt_query="${alt_query}&host=${HOST}"
    ALT_LINK="$(build_protocol_link "$PROTO" "$ALT_HOST" "443" "$alt_query" "(${friendly_region_alt})")"
  elif [ "$PROTO" = "vmess" ]; then
    # For VMESS, rebuild with ALT_HOST
    vmess_for_alt=$(echo "$VMESS_JSON" | sed "s|\"add\": \"$HOST\"|\"add\": \"$ALT_HOST\"|")
    ALT_LINK="vmess://$(echo "$vmess_for_alt" | base64 -w 0)"
  fi
  
  echo ""
  echo -e "${BOLD}${WHITE}Alternative Link (Short URL):${NC}"
  echo "$ALT_LINK"
else
  ALT_LINK="$SHARE_LINK"
fi

echo ""
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════╝${NC}"

# -------- Generate Data URIs --------
echo ""
print_section "Data URIs (JSON/Text)"
echo ""

# Prepare path/service info
PATH_INFO=""
if [ "$NETWORK" = "ws" ]; then
  PATH_INFO="Path: ${WSPATH}"
elif [ "$NETWORK" = "grpc" ]; then
  PATH_INFO="Service: ${WSPATH}"
fi

# Prepare optional params info
OPTIONAL_INFO=""
if [ -n "${SNI}" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}SNI: ${SNI}\n"
fi
if [ -n "${ALPN}" ] && [ "${ALPN}" != "h2,http/1.1" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}ALPN: ${ALPN}\n"
fi
if [ -n "${CUSTOM_ID}" ]; then
  OPTIONAL_INFO="${OPTIONAL_INFO}Custom ID: ${CUSTOM_ID}\n"
fi

# Data URI 1: Plain text configuration
CONFIG_TEXT="✅ XRAY DEPLOYMENT SUCCESS

Protocol: ${PROTO^^}
Host: ${HOST}
Port: 443
UUID/Password: ${UUID}
${PATH_INFO}
Network: ${NETWORK_DISPLAY} + TLS
${OPTIONAL_INFO}Share Link: ${SHARE_LINK}"

DATA_URI_TEXT="data:text/plain;base64,$(echo -n "$CONFIG_TEXT" | base64 -w 0)"
echo -e "${BOLD}Text Format:${NC}"
echo "$DATA_URI_TEXT"
echo ""

# Data URI 2: JSON configuration
if [ "$NETWORK" = "ws" ]; then
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "path": "${WSPATH}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
elif [ "$NETWORK" = "grpc" ]; then
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "service_name": "${WSPATH}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
else
  CONFIG_JSON=$(cat <<EOF
{
  "protocol": "${PROTO}",
  "host": "${HOST}",
  "port": 443,
  "uuid_password": "${UUID}",
  "network": "${NETWORK}",
  "network_display": "${NETWORK_DISPLAY}",
  "tls": true,
  "sni": "${SNI}",
  "alpn": "${ALPN}",
  "custom_id": "${CUSTOM_ID}",
  "share_link": "${SHARE_LINK}"
}
EOF
)
fi

DATA_URI_JSON="data:application/json;base64,$(echo -n "$CONFIG_JSON" | base64 -w 0)"
echo -e "${BOLD}JSON Format:${NC}"
echo "$DATA_URI_JSON"
echo ""

# -------- Send to Telegram --------
if [ -n "${BOT_TOKEN}" ] && [ -n "${CHAT_ID}" ]; then
  print_section "Sending to Telegram"
  # Send primary link (primary URL in HOST)
  #send_telegram "<b>🔗 PRIMARY (HOST):</b><pre>${SHARE_LINK}</pre>" 
  send_telegram "<b>🔗 PRIMARY (HOST):</b><pre>${ALT_LINK}</pre>"
  print_success "Configuration sent to Telegram"
fi

echo ""
echo -e "${BRIGHT_GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}    ✓ ${BRIGHT_WHITE}${BOLD}Installation Completed Successfully${NC}             ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}║${NC}                                                              ${BRIGHT_GREEN}${BOLD}║${NC}"
echo -e "${BRIGHT_GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BRIGHT_YELLOW}${BOLD}📌 Next Steps:${NC}"
echo -e "  ${BRIGHT_CYAN}1.${NC} Copy the link above (VLESS, VMESS, or TROJAN)"
echo -e "  ${BRIGHT_CYAN}2.${NC} Open your VPN client application"
echo -e "  ${BRIGHT_CYAN}3.${NC} Scan the QR code or paste the link"
echo -e "  ${BRIGHT_CYAN}4.${NC} Select and connect to the server"
echo ""
echo -e "${DIM}For more information, visit your VPN client's documentation.${NC}"

done
echo ""
