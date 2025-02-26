#!/usr/bin/env bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# GitHub repository base URL
GITHUB_BASE="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main"

# Logging functions
log_message() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Function to download a file with curl or wget fallback
download_file() {
  local url="$1"
  local output="$2"
  
  if command -v curl &> /dev/null; then
    curl -s "$url" -o "$output"
  elif command -v wget &> /dev/null; then
    wget -q "$url" -O "$output"
  else
    log_error "Neither curl nor wget is installed. Please install one of them."
    return 1
  fi
  
  if [ ! -s "$output" ]; then
    log_error "Failed to download $url"
    return 1
  fi
  
  return 0
}

# Brave process management functions
kill_brave() {
  log_message "Stopping Brave browser..."
  pkill -x "brave" >/dev/null 2>&1
  pkill -x "brave-browser" >/dev/null 2>&1
  pkill -f "flatpak run com.brave.Browser" >/dev/null 2>&1
  sleep 2
}

start_brave_with_urls() {
  local urls=("$@")
  if [[ "$IS_FLATPAK" == "true" ]]; then
    flatpak run com.brave.Browser "${urls[@]}" &
  elif [[ -n "$BRAVE_EXEC" ]]; then
    "$BRAVE_EXEC" "${urls[@]}" &
  else
    log_error "Brave executable not found"
    return 1
  fi
}

# Function to locate Brave files
locate_brave_files() {
  log_message "Locating Brave browser..."
  
  # Check for Flatpak installation first
  if command -v flatpak &> /dev/null; then
    BRAVE_FLATPAK=$(flatpak list --app | grep com.brave.Browser)
    if [[ -n "${BRAVE_FLATPAK}" ]]; then
      log_message "Flatpak Brave installation detected"
      BRAVE_EXEC="flatpak run com.brave.Browser"
      PREFERENCES_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default"
      POLICY_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/policies/managed"
      IS_FLATPAK=true
    fi
  fi

  # If not Flatpak, check standard installations
  if [[ -z "${BRAVE_EXEC}" ]]; then
    BRAVE_EXEC="$(command -v brave || command -v brave-browser || command -v brave-browser-stable)"
    if [[ -z "${BRAVE_EXEC}" ]]; then
      log_message "Brave browser not found. Would you like to install it? (y/n)"
      read -p "> " install_choice
      if [[ "${install_choice}" =~ ^[Yy]$ ]]; then
        install_brave_variant "stable"
        
        # Recheck for Brave after installation
        BRAVE_EXEC="$(command -v brave-browser || command -v brave || command -v brave-browser-stable)"
        if [[ -z "${BRAVE_EXEC}" ]]; then
          log_error "Installation failed or Brave not found in PATH"
          exit 1
        fi
      else
        log_error "Brave browser is required for this script"
        exit 1
      fi
    fi
    
    PREFERENCES_DIR="${HOME}/.config/BraveSoftware/Brave-Browser/Default"
    POLICY_DIR="/etc/brave/policies/managed"
    IS_FLATPAK=false
  fi

  # Create necessary directories
  mkdir -p "${POLICY_DIR}"
  mkdir -p "/usr/share/brave"
  mkdir -p "${PREFERENCES_DIR}"

  # Set the preferences file path
  BRAVE_PREFS="${PREFERENCES_DIR}/Preferences"

  log_message "Brave executable: ${BRAVE_EXEC}"
  log_message "Policy directory: ${POLICY_DIR}"
  log_message "Preferences directory: ${PREFERENCES_DIR}"
}
# Function to install Brave variant
install_brave_variant() {
  local variant="$1"
  local script_url=""
  
  case "$variant" in
    "stable")
      script_url="${GITHUB_BASE}/brave_install/install_brave_stable.sh"
      ;;
    "beta")
      script_url="${GITHUB_BASE}/brave_install/install_brave_beta.sh"
      ;;
    "nightly")
      script_url="${GITHUB_BASE}/brave_install/install_brave_nightly.sh"
      ;;
    *)
      log_error "Invalid Brave variant: $variant"
      return 1
      ;;
  esac
  
  # Download and execute the installation script
  local temp_script=$(mktemp)
  if download_file "$script_url" "$temp_script"; then
    chmod +x "$temp_script"
    "$temp_script"
    local result=$?
    rm "$temp_script"
    return $result
  else
    return 1
  fi
}

# Function to create desktop entry
create_desktop_entry() {
  log_message "Creating desktop entry for Brave Debloat..."
  
  # Download and install the icon
  local icon_url="${GITHUB_BASE}/brave_icon.png"
  local icon_path="/usr/share/icons/brave_debloat.png"
  
  log_message "Downloading Brave icon..."
  if download_file "$icon_url" "$icon_path"; then
    chmod 644 "$icon_path"
    log_message "Icon installed successfully"
  else
    log_error "Failed to download icon, using default"
  fi
  
  # Create the desktop entry file
  local desktop_file="/usr/share/applications/brave-debloat.desktop"
  
  cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Name=Brave Debloat
Exec=brave --enable-features=UseOzonePlatform --ozone-platform=wayland
Icon=/usr/share/icons/brave_debloat.png
Type=Application
Categories=Network;WebBrowser;
Terminal=false
StartupNotify=true
Comment=Debloated and optimized Brave browser
EOF

  chmod 644 "$desktop_file"
  log_message "Desktop entry created successfully"
  return 0
}

# Function to apply a policy from GitHub
apply_policy() {
  local policy_name="$1"
  local policy_file="${POLICY_DIR}/${policy_name}.json"
  
  log_message "Applying ${policy_name} policy..."
  if download_file "${GITHUB_BASE}/policies/${policy_name}.json" "$policy_file"; then
    chmod 644 "$policy_file"
    log_message "${policy_name} policy applied successfully"
    return 0
  else
    log_error "Failed to apply ${policy_name} policy"
    return 1
  fi
}

# Function to modify dashboard preferences
modify_dashboard_preferences() {
  local preferences_file="${BRAVE_PREFS}"
  
  # Ensure the Preferences directory exists
  mkdir -p "${PREFERENCES_DIR}"
  
  # Create or modify Preferences file
  if [[ ! -f "${preferences_file}" ]]; then
    echo "{}" > "${preferences_file}"
  fi
  
  # Use jq to modify the Preferences file
  local temp_file="${preferences_file}.tmp"
  jq '.brave = (.brave // {}) | 
      .brave.stats = (.brave.stats // {}) | 
      .brave.stats.enabled = false | 
      .brave.today = (.brave.today // {}) | 
      .brave.today.should_show_brave_today_widget = false | 
      .brave.new_tab_page = (.brave.new_tab_page // {}) | 
      .brave.new_tab_page.show_clock = true | 
      .brave.new_tab_page.show_search_widget = false |
      .brave.new_tab_page.show_branded_background_image = false |
      .brave.new_tab_page.show_cards = false |
      .brave.new_tab_page.show_background_image = false |
      .brave.new_tab_page.show_stats = false |
      .brave.new_tab_page.show_shortcuts = false' "${preferences_file}" > "${temp_file}"
  mv "${temp_file}" "${preferences_file}"
  chmod 644 "${preferences_file}"
  log_message "Modified dashboard preferences - removed all widgets, added clock"
}

# Function to apply default optimizations
apply_default_optimizations() {
  log_message "Applying default optimizations..."
  
  apply_policy "brave_optimizations"
  apply_policy "adblock"
  apply_policy "privacy"
  apply_policy "ui"
  apply_policy "features"  # Added features.json
  create_desktop_entry
  modify_dashboard_preferences
  
  # Enable the flag in Local State
  LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
  if [[ -f "${LOCAL_STATE}" ]]; then
    # Check if the file contains the browser.enabled_labs_experiments key
    if jq -e '.browser.enabled_labs_experiments' "${LOCAL_STATE}" >/dev/null 2>&1; then
      # Add the flag if it doesn't exist
      jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
    else
      # Create the key if it doesn't exist
      jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
    fi
    mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
    log_message "Enabled advanced ad blocking flag in browser flags"
  fi
  
  log_message "Default optimizations applied successfully"
  log_message "Please restart Brave browser for changes to take effect"
}

# Function to install Brave and optimize
install_brave_and_optimize() {
  log_message "Starting Brave installation and optimization process..."
  
  # Step 1: Select Brave variant
  log_message "Select Brave variant to install..."
  echo "1. Brave Stable"
  echo "2. Brave Beta"
  echo "3. Brave Nightly"
  read -p "Enter your choice [1-3]: " variant
  
  case $variant in
    1) variant_name="stable" ;;
    2) variant_name="beta" ;;
    3) variant_name="nightly" ;;
    *) log_error "Invalid selection. Aborting."; return 1 ;;
  esac
  
  # Step 2: Install selected Brave variant
  install_brave_variant "$variant_name"
  if [ $? -ne 0 ]; then
    log_error "Failed to install Brave browser. Aborting."
    return 1
  fi
  
  # Step 3: Apply default optimizations
  log_message "Applying default optimizations and debloating Brave..."
  apply_default_optimizations
  
  # Step 4: Select search engine
  log_message "Select default search engine..."
  set_search_engine
  
  # Step 5: Present extension selection UI
  log_message "Select extensions to install..."
  install_recommended_extensions
  
  log_message "Brave installation and optimization completed successfully."
  log_message "Please restart Brave browser for all changes to take effect."
}
# Function to set search engine
set_search_engine() {
  while true; do
    clear
    echo "=== Search Engine Selection ==="
    echo "1. Brave Search (Privacy focused but collects data)"
    echo "2. DuckDuckGo (Privacy focused but collects data)"
    echo "3. SearXNG (Recommended but only if self-hosted)"
    echo "4. Whoogle (Recommended but only if self-hosted)"
    echo "5. Yandex (enjoy russian botnet)"
    echo "6. Kagi (excellent engine, but a paid service)"
    echo "7. Google (welcome to the botnet)"
    echo "8. Bing (enjoy your AIDs)"
    echo "9. Back to main menu"
    
    read -p "Enter your choice [1-9]: " search_choice
    local policy_file="${POLICY_DIR}/search_provider.json"
    
    case ${search_choice} in
      1)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Brave",
  "DefaultSearchProviderSearchURL": "https://search.brave.com/search?q={searchTerms}"
}
EOF
        log_message "Search engine set to Brave Search"
        break
        ;;
      2)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "DuckDuckGo",
  "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}"
}
EOF
        log_message "Search engine set to DuckDuckGo"
        break
        ;;
      3)
        read -p "Enter your SearXNG instance URL: " searx_url
        if [[ "${searx_url}" =~ ^https?:// ]]; then
          cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "SearXNG",
  "DefaultSearchProviderSearchURL": "${searx_url}/search?q={searchTerms}"
}
EOF
          log_message "Search engine set to SearXNG"
          break
        else
          log_error "Invalid URL format"
          sleep 2
        fi
        ;;
      4)
        read -p "Enter your Whoogle instance URL: " whoogle_url
        if [[ "${whoogle_url}" =~ ^https?:// ]]; then
          cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Whoogle",
  "DefaultSearchProviderSearchURL": "${whoogle_url}/search?q={searchTerms}"
}
EOF
          log_message "Search engine set to Whoogle"
          break
        else
          log_error "Invalid URL format"
          sleep 2
        fi
        ;;
      5)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Yandex",
  "DefaultSearchProviderSearchURL": "https://yandex.com/search/?text={searchTerms}"
}
EOF
        log_message "Search engine set to Yandex"
        break
        ;;
      6)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Kagi",
  "DefaultSearchProviderSearchURL": "https://kagi.com/search?q={searchTerms}"
}
EOF
        log_message "Search engine set to Kagi"
        break
        ;;
      7)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}"
}
EOF
        log_message "Search engine set to Google"
        break
        ;;
      8)
        cat > "${policy_file}" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Bing",
  "DefaultSearchProviderSearchURL": "https://www.bing.com/search?q={searchTerms}"
}
EOF
        log_message "Search engine set to Bing"
        break
        ;;
      9)
        return
        ;;
      *)
        log_error "Invalid option"
        sleep 2
        ;;
    esac
    chmod 644 "${policy_file}"
  done
}

# Function to toggle experimental ad blocking
toggle_experimental_adblock() {
  log_message "Checking current advanced ad blocking status..."
  if [[ -f "${BRAVE_PREFS}" ]]; then
    if jq -e '.brave.ad_block.regional_filters["564C3B75-8731-404C-AD7C-5683258BA0B0"].enabled // false' "${BRAVE_PREFS}" >/dev/null 2>&1; then
      log_message "Advanced Ad Blocking is currently ENABLED"
      read -p "Would you like to disable it? (y/n): " disable_choice
      if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
        # Remove policy file
        rm -f "${POLICY_DIR}/adblock.json"
        
        # Update preferences
        jq '.brave = (.brave // {}) | 
            .brave.shields = (.brave.shields // {}) |
            .brave.shields.experimental_filters_enabled = false |
            .brave.ad_block = (.brave.ad_block // {}) |
            .brave.ad_block.regional_filters = (.brave.ad_block.regional_filters // {}) |
            .brave.ad_block.regional_filters["564C3B75-8731-404C-AD7C-5683258BA0B0"] = {"enabled": false}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        
        # Disable the flag in Local State
        LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
        if [[ -f "${LOCAL_STATE}" ]]; then
          jq 'del(.browser.enabled_labs_experiments[] | select(. == "brave-adblock-experimental-list-default@1"))' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
          mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
        fi
        
        # Remove flag from desktop entry
        if grep -q -- "--enable-features=brave-adblock-experimental-list-default" "/usr/share/applications/brave-debloat.desktop"; then
          sed -i 's/--enable-features=brave-adblock-experimental-list-default//' "/usr/share/applications/brave-debloat.desktop"
          log_message "Removed advanced ad blocking flag from desktop entry"
        fi
        
        log_message "Advanced Ad Blocking has been DISABLED"
      fi
    else
      log_message "Advanced Ad Blocking is currently DISABLED"
      read -p "Would you like to enable it? (y/n): " enable_choice
      if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
        # Create policy file
        cat > "${POLICY_DIR}/adblock.json" << EOF
{
  "ShieldsAdvancedView": true,
  "BraveExperimentalAdblockEnabled": true
}
EOF
        chmod 644 "${POLICY_DIR}/adblock.json"
        
        # Update preferences with direct UUID modification
        jq '.brave = (.brave // {}) | 
            .brave.shields = (.brave.shields // {}) |
            .brave.shields.experimental_filters_enabled = true |
            .brave.shields.advanced_view_enabled = true |
            .brave.ad_block = (.brave.ad_block // {}) |
            .brave.ad_block.regional_filters = (.brave.ad_block.regional_filters // {}) |
            .brave.ad_block.regional_filters["564C3B75-8731-404C-AD7C-5683258BA0B0"] = {"enabled": true}' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
        
        # Enable the flag in Local State
        LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
        if [[ -f "${LOCAL_STATE}" ]]; then
          # Check if the file contains the browser.enabled_labs_experiments key
          if jq -e '.browser.enabled_labs_experiments' "${LOCAL_STATE}" >/dev/null 2>&1; then
            # Add the flag if it doesn't exist
            jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
          else
            # Create the key if it doesn't exist
            jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
          fi
          mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
          log_message "Enabled advanced ad blocking flag in browser flags"
        fi
        
        # Add flag to desktop entry
        if grep -q "Exec=brave" "/usr/share/applications/brave-debloat.desktop"; then
          if ! grep -q -- "--enable-features=brave-adblock-experimental-list-default" "/usr/share/applications/brave-debloat.desktop"; then
            sed -i 's/Exec=brave/Exec=brave --enable-features=brave-adblock-experimental-list-default/' "/usr/share/applications/brave-debloat.desktop"
            log_message "Added advanced ad blocking flag to desktop entry"
          fi
        fi
        
        log_message "Advanced Ad Blocking has been ENABLED"
      fi
    fi
    log_message "Please COMPLETELY QUIT Brave browser and restart for changes to take effect"
    log_message "After restart, check brave://components/ and update 'Brave Ad Block Updater' if needed"
  else
    log_error "Preferences file not found"
  fi
}
# Function to install recommended extensions - Fixed for permission issues
install_recommended_extensions() {
  log_message "Installing recommended Brave extensions..."
  
  # Download extension data
  local temp_file=$(mktemp)
  if ! download_file "${GITHUB_BASE}/policies/consolidated_extensions.json" "$temp_file"; then
    log_error "Failed to download extension data"
    rm "$temp_file"
    return 1
  fi

  # Simplified approach - just list all extensions with numbers
  echo -e "\n=== Available Extensions ==="
  local i=1
  declare -A extension_map
  
  # Get all extensions regardless of category
  while read -r ext_line; do
    local id=$(echo "$ext_line" | cut -d'|' -f1)
    local name=$(echo "$ext_line" | cut -d'|' -f2)
    local description=$(echo "$ext_line" | cut -d'|' -f3)
    local recommended=$(echo "$ext_line" | cut -d'|' -f4)
    
    # Mark recommended extensions with an asterisk
    local mark=""
    if [[ "$recommended" == "true" ]]; then
      mark="*"
    fi
    
    printf "%2d. %-25s - %s %s\n" "$i" "$name" "$description" "$mark"
    extension_map["$i"]="$id|$name"
    ((i++))
  done < <(jq -r '.categories | to_entries[] | .value[] | [.id, .name, .description, (.recommended|tostring)] | join("|")' "$temp_file")
  
  echo -e "\n* = Recommended extension"
  
  # Get user selection
  echo -e "\nEnter space-separated numbers (1-$((i-1))) to select extensions"
  echo -n "Press Enter to install recommended extensions only: "
  read -a selections
  
  # Process selections
  local selected_exts=()
  if [ ${#selections[@]} -eq 0 ]; then
    # Get recommended extensions
    while read -r ext_line; do
      local id=$(echo "$ext_line" | cut -d'|' -f1)
      local name=$(echo "$ext_line" | cut -d'|' -f2)
      selected_exts+=("$id|$name")
    done < <(jq -r '.recommended_ids[] as $id | .categories | to_entries[] | .value[] | select(.id == $id) | [$id, .name] | join("|")' "$temp_file")
  else
    # Process user selections
    for num in "${selections[@]}"; do
      if [[ -n "${extension_map[$num]}" ]]; then
        selected_exts+=("${extension_map[$num]}")
      else
        log_error "Invalid selection: $num (ignoring)"
      fi
    done
  fi

  rm "$temp_file"

  # Open extension pages
  if [ ${#selected_exts[@]} -gt 0 ]; then
    log_message "Closing any running Brave browser instances..."
    # Use more specific process names to avoid killing our script
    pkill -f "brave-browser" || true
    pkill -f "brave " || true
    pkill -f "/opt/brave" || true
    pkill -f "flatpak run com.brave.Browser" || true
    sleep 2
    
    # Build URLs for direct launch
    local urls=""
    echo -e "\nSelected extensions:"
    for ext in "${selected_exts[@]}"; do
      IFS='|' read -r id name <<< "$ext"
      echo "- $name"
      urls+=" https://chrome.google.com/webstore/detail/$id"
    done
    
    # Open the browser with extension pages
    log_message "Opening extensions in Brave browser..."
    
    if [ "$EUID" -eq 0 ]; then
      # Running as root, need to switch to actual user
      ACTUAL_USER=$(logname || echo "$SUDO_USER")
      if [ -z "$ACTUAL_USER" ]; then
        log_error "Could not determine the actual user"
        return 1
      fi
      
      # Direct command execution without creating a script file
      log_message "Launching browser as user $ACTUAL_USER..."
      sudo -u "$ACTUAL_USER" bash -c "brave$urls &"
      
      # If that fails, provide instructions
      echo -e "\nIf Brave doesn't open automatically, please run this command in your terminal:"
      echo "brave$urls"
    else
      # Not running as root, launch directly
      log_message "Launching Brave browser..."
      bash -c "brave$urls &"
    fi
    
    # Wait for user to complete installation
    echo -e "\nPlease install the selected extensions in the browser."
    read -p "Have you completed installing the extensions? (y/n): " completed
    
    if [[ "$completed" =~ ^[Yy]$ ]]; then
      read -p "Would you like to apply default optimizations now? (y/n): " optimize
      if [[ "$optimize" =~ ^[Yy]$ ]]; then
        apply_default_optimizations
      fi
    else
      log_message "You can run the script again later to complete optimization."
    fi
  else
    log_message "No extensions selected for installation."
  fi
}

# Show menu function
show_menu() {
  clear
  echo "
██████╗ ██████╗ █████╗ ██╗   ██╗███████╗     ██████╗ ███████╗██████╗ ██╗      ██████╗  █████╗ ████████╗
██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔════╝    ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗██╔══██╗╚══██╔══╝
██████╔╝██████╔╝███████║██║   ██║█████╗      ██║  ██║█████╗  ██████╔╝██║     ██║   ██║███████║   ██║   
██╔══██╗██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝      ██║  ██║██╔══╝  ██╔══██╗██║     ██║   ██║██╔══██║   ██║   
██████╔╝██║  ██║██║  ██║ ╚████╔╝ ███████╗    ██████╔╝███████╗██████╔╝███████╗╚██████╔╝██║  ██║   ██║   
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝    ╚═════╝ ╚══════╝╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
"

  echo "A script to debloat Brave browser and apply optimizations..."
  echo "*Note I am working on a new version of this script to cover smoothbrain Win and Mac users."
  echo
  echo "=== Brave Browser Optimization Menu ==="
  echo "1. Apply Default Optimizations (Recommended)"
  echo "   Enables core performance features and removes unnecessary bloat"
  echo
  echo "2. Install Brave and apply optimizations"
  echo "   Install Brave browser and apply recommended optimizations"
  echo
  echo "3. Change Search Engine"
  echo "   Choose from DuckDuckGo, SearXNG, Whoogle or traditional options"
  echo
  echo "4. Toggle Hardware Acceleration"
  echo "   Improves rendering performance using your GPU"
  echo
  echo "5. Disable Analytics & Data Collection"
  echo "   Stops background analytics and telemetry"
  echo
  echo "6. Enable Custom Scriptlets (Advanced)"
  echo "   WARNING: Only for advanced users. Allows custom JavaScript injection"
  echo
  echo "7. Disable Background Running"
  echo "   WARNING: May cause instability"
  echo
  echo "8. Toggle Memory Saver"
  echo "   Reduces memory usage by suspending inactive tabs"
  echo
  echo "9. UI Improvements"
  echo "   Shows full URLs, enables wide address bar, and bookmarks bar"
  echo
  echo "10. Dashboard Customization"
  echo "    Removes widgets and customizes the new tab page"
  echo
  echo "11. Remove Brave Rewards/VPN/Wallet"
  echo "    Disables cryptocurrency and rewards features"
  echo
  echo "12. Toggle Experimental Ad Blocking (experimental)"
  echo "    Enhanced ad blocking - Will check current status"
  echo
  echo "13. Install Recommended Brave extensions"
  echo "    Installs a curated set of recommended extensions"
  echo
  echo "14. Exit"
  echo
  echo "You can select multiple options by entering numbers separated by spaces (e.g., 4 5 8)"
  echo "Note: Options 1 and 2 cannot be combined with other options"
  echo
}

# Main function
main() {
  locate_brave_files
  
  while true; do
    show_menu
    
    read -p "Enter your choice(s) [1-14]: " choices
    
    # Convert input to array
    IFS=' ' read -ra selected_options <<< "$choices"
    
    # Check for exclusive options (1 and 2)
    local has_exclusive=0
    for choice in "${selected_options[@]}"; do
      if [[ "$choice" == "1" || "$choice" == "2" ]]; then
        has_exclusive=1
        break
      fi
    done
    
    if [[ $has_exclusive -eq 1 && ${#selected_options[@]} -gt 1 ]]; then
      log_error "Options 1 and 2 cannot be combined with other options"
      sleep 2.5
      continue
    fi
    
    # Process each selected option
    for choice in "${selected_options[@]}"; do
      case ${choice} in
        1)
          apply_default_optimizations
          sleep 2.5
          ;;
        2)
          install_brave_and_optimize
          sleep 2.5
          ;;
        3)
          set_search_engine
          sleep 2.5
          ;;
        4)
          log_message "Toggling hardware acceleration..."
          cat > "${POLICY_DIR}/hardware.json" << EOF
{
  "HardwareAccelerationModeEnabled": true
}
EOF
          chmod 644 "${POLICY_DIR}/hardware.json"
          log_message "Hardware acceleration enabled"
          sleep 2.5
          ;;
        5)
          log_message "Disabling analytics and data collection..."
          cat > "${POLICY_DIR}/privacy.json" << EOF
{
  "MetricsReportingEnabled": false,
  "CloudReportingEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "AutomaticallySendAnalytics": false,
  "DnsOverHttpsMode": "automatic"
}
EOF
          chmod 644 "${POLICY_DIR}/privacy.json"
          log_message "Analytics and data collection disabled"
          sleep 2.5
          ;;
        6)
          log_message "WARNING: Custom scriptlets are an advanced feature"
          cat > "${POLICY_DIR}/scriptlets.json" << EOF
{
  "ShieldsAdvancedView": true,
  "EnableCustomScriptlets": true
}
EOF
          chmod 644 "${POLICY_DIR}/scriptlets.json"
          log_message "Custom scriptlets enabled"
          sleep 2.5
          ;;
        7)
          log_message "WARNING: Disabling background running may cause instability"
          cat > "${POLICY_DIR}/background.json" << EOF
{
  "BackgroundModeEnabled": false
}
EOF
          chmod 644 "${POLICY_DIR}/background.json"
          log_message "Background running disabled"
          sleep 2.5
          ;;
        8)
          log_message "Toggling Memory Saver..."
          cat > "${POLICY_DIR}/memory.json" << EOF
{
  "MemorySaverEnabled": true
}
EOF
          chmod 644 "${POLICY_DIR}/memory.json"
          log_message "Memory Saver enabled"
          sleep 2.5
          ;;
        9)
          log_message "Applying UI improvements..."
          cat > "${POLICY_DIR}/ui.json" << EOF
{
  "ShowFullURLs": true,
  "WideAddressBar": true,
  "BookmarksBarEnabled": true
}
EOF
          chmod 644 "${POLICY_DIR}/ui.json"
          log_message "UI improvements applied"
          sleep 2.5
          ;;
        10)
          log_message "Customizing dashboard..."
          modify_dashboard_preferences
          sleep 2.5
          ;;
        11)
          log_message "Removing Brave Rewards/VPN/Wallet..."
          apply_policy "features"
          log_message "Brave Rewards/VPN/Wallet disabled and icons hidden"
          sleep 2.5
          ;;
        12)
          toggle_experimental_adblock
          sleep 4
          ;;
        13)
          install_recommended_extensions
          sleep 2.5
          ;;
        14)
          log_message "Exiting...
Thank you for using Brave debloat, lets make Brave great again."
          sleep 2.5
          exit 0
          ;;
        *)
          log_error "Invalid option: $choice"
          sleep 2.5
          ;;
      esac
    done
    
    # If we've processed all options, show a summary
    if [ ${#selected_options[@]} -gt 0 ]; then
      log_message "All selected options have been processed."
      log_message "Please restart Brave browser for all changes to take effect."
      sleep 2.5
    fi
  done
}
# Check for required dependencies
if ! command -v jq &> /dev/null; then
  log_error "jq is not installed. Please install it first."
  exit 1
fi

# Run main script
main
