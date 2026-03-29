#!/usr/bin/env bash
# ========== PROTOCOL LIBRARY - Unified Protocol Functions ==========
# This library consolidates all protocol-related functions to reduce code duplication
# Source this file in install.sh to use these functions

# -------- Build Protocol Links --------
# Builds a connection link for the specified protocol
# Usage: build_protocol_link <protocol> <host> <port> <query_params> <fragment>
build_protocol_link() {
  local proto="$1"
  local host="$2"
  local port="$3"
  local query_params="$4"
  local fragment="$5"
  
  case "$proto" in
    vless)
      echo "vless://${UUID}@${host}:${port}?${query_params}#${fragment}"
      ;;
    vmess)
      # VMESS requires base64 encoding of JSON config
      local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "$SERVICE",
  "add": "$host",
  "port": "$port",
  "id": "$UUID",
  "aid": "0",
  "net": "$NETWORK",
  "type": "none",
  "host": "$host",
  "path": "$WSPATH",
  "tls": "tls"
}
EOF
)
      if [ -n "${SNI}" ]; then
        vmess_json=$(echo "$vmess_json" | sed "s/}/,\"sni\":\"${SNI}\"}/")
      fi
      if [ -n "${ALPN}" ]; then
        vmess_json=$(echo "$vmess_json" | sed "s/}/,\"alpn\":\"${ALPN}\"}/")
      fi
      echo "vmess://$(echo "$vmess_json" | base64 -w 0)"
      ;;
    trojan)
      echo "trojan://${UUID}@${host}:${port}?${query_params}#${fragment}"
      ;;
    *)
      echo ""
      ;;
  esac
}

# -------- Get Protocol Color --------
# Returns the color code for each protocol
# Usage: get_protocol_color <protocol>
get_protocol_color() {
  local proto="$1"
  
  case "$proto" in
    vless)
      echo "${BRIGHT_CYAN}"
      ;;
    vmess)
      echo "${BRIGHT_MAGENTA}"
      ;;
    trojan)
      echo "${BRIGHT_RED}"
      ;;
    *)
      echo "${BRIGHT_WHITE}"
      ;;
  esac
}

# -------- Get Protocol Display Name --------
# Returns the uppercase display name
# Usage: get_protocol_display <protocol>
get_protocol_display() {
  local proto="$1"
  echo "${proto^^}"
}

# -------- Print Protocol Link --------
# Prints a formatted protocol link with colors
# Usage: print_protocol_link <protocol> <link>
print_protocol_link() {
  local proto="$1"
  local link="$2"
  local color="$(get_protocol_color "$proto")"
  local display="$(get_protocol_display "$proto")"
  
  echo ""
  echo -e "${color}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${color}${BOLD}${display} Link:${NC}"
  echo -e "${color}${DIM}${link}${NC}"
  echo -e "${color}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# -------- Select Protocol (Interactive) --------
# Prompts user to select protocol (only in custom mode)
# Sets global $PROTO variable
# Usage: select_protocol_interactive
select_protocol_interactive() {
  if [ "$PRESET_MODE" = "custom" ]; then
    print_section "Protocol Selection"
    echo ""
    echo -e "  ${BOLD}${BRIGHT_CYAN}1${NC} ${BRIGHT_CYAN}VLESS${NC}       ${DIM}Fast, modern, lightweight${NC}"
    echo -e "  ${BOLD}${BRIGHT_YELLOW}2${NC} ${BRIGHT_YELLOW}VMESS${NC}       ${DIM}Compatible, widely supported${NC}"
    echo -e "  ${BOLD}${BRIGHT_RED}3${NC} ${BRIGHT_RED}TROJAN${NC}      ${DIM}Camouflages as HTTPS server${NC}"
    echo ""
    
    local proto_choice=""
    while [ -z "${proto_choice:-}" ]; do
      read -rp "$(echo -e "${BOLD}${BRIGHT_BLUE}Select protocol${NC} (required): ")" proto_choice
    done
    
    case "$proto_choice" in
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
        return 1
        ;;
    esac
  else
    PROTO="${PRESET_PROTO:-vless}"
    print_success "Using preset protocol: $PROTO"
  fi
}

# -------- Generate All Protocol Links --------
# Generates primary and alternative links for the selected protocol
# Sets global variables: $SHARE_LINK, $ALT_LINK
# Usage: generate_all_protocol_links
generate_all_protocol_links() {
  # Build fragment with custom ID
  local link_fragment="xray"
  if [ -n "${CUSTOM_ID}" ]; then
    link_fragment="(${CUSTOM_ID})"
  fi

  # Generate primary link
  SHARE_LINK="$(build_protocol_link "$PROTO" "$HOST" "443" "$QUERY_PARAMS" "$link_fragment")"
  print_protocol_link "$PROTO" "$SHARE_LINK"

  # Generate alternative link if available
  if [ "$ALT_HOST" != "$HOST" ] 2>/dev/null; then
    local friendly_region="$(get_region_name "$REGION")"
    local friendly_region_alt="${friendly_region}_SN"
    
    # Adjust query parameters for alternative host
    if [ "$PROTO" = "vless" ] || [ "$PROTO" = "trojan" ]; then
      local alt_query=$(echo "$QUERY_PARAMS" | sed 's/&host=[^&]*//g')
      alt_query="${alt_query}&host=${HOST}"
      ALT_LINK="$(build_protocol_link "$PROTO" "$ALT_HOST" "443" "$alt_query" "${friendly_region_alt}")"
    elif [ "$PROTO" = "vmess" ]; then
      # For VMESS, we need to rebuild with ALT_HOST
      local alt_vmess_json=$(echo "$VMESS_JSON" | sed "s|\"add\": \"$HOST\"|\"add\": \"$ALT_HOST\"|")
      ALT_LINK="vmess://$(echo "$alt_vmess_json" | base64 -w 0)"
    fi
    
    echo ""
    echo -e "${BOLD}${WHITE}Alternative Link (Short URL):${NC}"
    echo "$ALT_LINK"
  else
    ALT_LINK="$SHARE_LINK"
  fi
}

# -------- Build Config JSON --------
# Generates configuration in JSON format
# Usage: build_config_json <network_type>
build_config_json() {
  local network_type="${1:-ws}"
  
  if [ "$network_type" = "ws" ]; then
    cat <<EOF
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
  elif [ "$network_type" = "grpc" ]; then
    cat <<EOF
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
  else
    cat <<EOF
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
  fi
}

# -------- Build Config Text --------
# Generates configuration in plain text format
# Usage: build_config_text
build_config_text() {
  local path_info=""
  if [ "$NETWORK" = "ws" ]; then
    path_info="Path: ${WSPATH}"
  elif [ "$NETWORK" = "grpc" ]; then
    path_info="Service: ${WSPATH}"
  fi

  local optional_info=""
  if [ -n "${SNI}" ]; then
    optional_info="${optional_info}SNI: ${SNI}\n"
  fi
  if [ -n "${ALPN}" ] && [ "${ALPN}" != "h2,http/1.1" ]; then
    optional_info="${optional_info}ALPN: ${ALPN}\n"
  fi
  if [ -n "${CUSTOM_ID}" ]; then
    optional_info="${optional_info}Custom ID: ${CUSTOM_ID}\n"
  fi

  cat <<EOF
✅ XRAY DEPLOYMENT SUCCESS

Protocol: ${PROTO^^}
Host: ${HOST}
Port: 443
UUID/Password: ${UUID}
${path_info}
Network: ${NETWORK_DISPLAY} + TLS
${optional_info}Share Link: ${SHARE_LINK}
EOF
}

# Export functions for use in main script
export -f build_protocol_link
export -f get_protocol_color
export -f get_protocol_display
export -f print_protocol_link
export -f select_protocol_interactive
export -f generate_all_protocol_links
export -f build_config_json
export -f build_config_text
