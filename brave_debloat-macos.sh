#!/bin/bash

# Brave Debloat Script for macOS
# Based on the Linux version by nomadxxxx

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# GitHub repository base URL
GITHUB_BASE="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main"

# macOS specific paths
BRAVE_APP="/Applications/Brave Browser.app"
BRAVE_CONTENTS="${BRAVE_APP}/Contents"
BRAVE_RESOURCES="${BRAVE_CONTENTS}/Resources"
BRAVE_FRAMEWORK="${BRAVE_CONTENTS}/Frameworks/Brave Browser Framework.framework"
POLICY_DIR="${BRAVE_FRAMEWORK}/Resources/policies"
USER_DATA_DIR="${HOME}/Library/Application Support/BraveSoftware/Brave-Browser"
DEFAULT_PROFILE_DIR="${USER_DATA_DIR}/Default"
BRAVE_PREFS="${DEFAULT_PROFILE_DIR}/Preferences"
LOCAL_STATE="${USER_DATA_DIR}/Local State"

# Logging functions
log_message() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
  echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Function to download a file with curl
download_file() {
  local url="$1"
  local output="$2"
  
  curl -s "$url" -o "$output"
  
  if [ ! -s "$output" ]; then
    log_error "Failed to download $url"
    return 1
  fi
  
  return 0
}

# Function to check if Brave is installed
check_brave_installation() {
  log_message "Checking Brave browser installation..."
  
  if [ ! -d "$BRAVE_APP" ]; then
    log_message "Brave browser not found. Would you like to install it? (y/n)"
    read -p "> " install_choice
    if [[ "${install_choice}" =~ ^[Yy]$ ]]; then
      install_brave
      
      # Recheck for Brave after installation
      if [ ! -d "$BRAVE_APP" ]; then
        log_error "Installation failed or Brave not found"
        exit 1
      fi
    else
      log_error "Brave browser is required for this script"
      exit 1
    fi
  fi
  
  # Create necessary directories
  mkdir -p "${POLICY_DIR}"
  mkdir -p "${DEFAULT_PROFILE_DIR}"
  
  log_message "Brave browser found at: ${BRAVE_APP}"
  log_message "Policy directory: ${POLICY_DIR}"
  log_message "User data directory: ${USER_DATA_DIR}"
}

# Function to install Brave on macOS
install_brave() {
  log_message "Installing Brave browser..."
  
  # Download Brave DMG
  local dmg_url="https://laptop-updates.brave.com/latest/osx"
  local dmg_path="/tmp/brave.dmg"
  
  log_message "Downloading Brave browser..."
  if download_file "$dmg_url" "$dmg_path"; then
    log_message "Mounting Brave disk image..."
    hdiutil attach "$dmg_path" -nobrowse
    
    log_message "Installing Brave browser..."
    cp -R "/Volumes/Brave Browser/Brave Browser.app" /Applications/
    
    log_message "Unmounting Brave disk image..."
    hdiutil detach "/Volumes/Brave Browser" -force
    
    rm "$dmg_path"
    log_message "Brave browser installed successfully"
    return 0
  else
    log_error "Failed to download Brave browser"
    return 1
  fi
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
  mkdir -p "${DEFAULT_PROFILE_DIR}"
  
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
  apply_policy "features"
  modify_dashboard_preferences
  
  # Enable the flag in Local State
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

# Function to install dashboard customizer extension
install_dashboard_customizer() {
  log_message "Installing Brave Dashboard Customizer extension..."
  
  # Create directory if it doesn't exist
  mkdir -p "${USER_DATA_DIR}/extensions"
  
  # Download the extension
  local crx_url="${GITHUB_BASE}/brave-dashboard-customizer/brave-dashboard-customizer.crx"
  local crx_path="${USER_DATA_DIR}/extensions/brave-dashboard-customizer.crx"
  local ext_dir="${USER_DATA_DIR}/extensions/dashboard-extension"
  
  if download_file "$crx_url" "$crx_path"; then
    chmod 644 "$crx_path"
    log_message "Dashboard Customizer extension downloaded successfully"
    
    # Unpack the CRX file
    log_message "Unpacking extension..."
    mkdir -p "$ext_dir"
    unzip -o "$crx_path" -d "$ext_dir" >/dev/null 2>&1
    
    # Create a permissions policy file for the extension
    local ext_id=$(basename "$(find "$ext_dir" -name "manifest.json" -exec dirname {} \;)")
    cat > "${POLICY_DIR}/extension_settings.json" << EOF
{
  "ExtensionSettings": {
    "$ext_id": {
      "installation_mode": "normal_installed",
      "update_url": "https://clients2.google.com/service/update2/crx",
      "toolbar_pin": "force_pinned"
    }
  }
}
EOF
    chmod 644 "${POLICY_DIR}/extension_settings.json"
    
    # Create a macOS launch agent to load the extension
    local launch_agent_dir="${HOME}/Library/LaunchAgents"
    local launch_agent_file="${launch_agent_dir}/com.brave.extension.plist"
    
    mkdir -p "$launch_agent_dir"
    
    cat > "$launch_agent_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.brave.extension</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Brave Browser.app/Contents/MacOS/Brave Browser</string>
        <string>--load-extension=${ext_dir}</string>
        <string>--homepage=chrome://newtab</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    
    chmod 644 "$launch_agent_file"
    log_message "Created launch agent for Dashboard Customizer"
    
    # Create an AppleScript to launch Brave with the extension
    local applescript_dir="${HOME}/Applications"
    local applescript_file="${applescript_dir}/Brave Debloat.app"
    
    mkdir -p "$applescript_dir"
    
    # Create the AppleScript application bundle
    mkdir -p "${applescript_file}/Contents/MacOS"
    mkdir -p "${applescript_file}/Contents/Resources"
    
    # Create Info.plist
    cat > "${applescript_file}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>brave-debloat</string>
    <key>CFBundleIconFile</key>
    <string>brave_icon</string>
    <key>CFBundleIdentifier</key>
    <string>com.brave.debloat</string>
    <key>CFBundleName</key>
    <string>Brave Debloat</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
EOF
    
    # Create the executable script
    cat > "${applescript_file}/Contents/MacOS/brave-debloat" << EOF
#!/bin/bash
open -a "Brave Browser" --args --load-extension="${ext_dir}" --homepage=chrome://newtab
EOF
    
    chmod +x "${applescript_file}/Contents/MacOS/brave-debloat"
    
    # Download and add the icon
    download_file "${GITHUB_BASE}/brave_icon.png" "${applescript_file}/Contents/Resources/brave_icon.png"
    
    log_message "Created Brave Debloat application"
    log_message "Dashboard Customizer extension installed successfully"
    return 0
  else
    log_error "Failed to download Dashboard Customizer extension"
    return 1
  fi
}

# Function to install extension from CRX file
install_extension_from_crx() {
  local ext_id="$1"
  local ext_name="$2"
  local crx_url="$3"
  local ext_dir="${USER_DATA_DIR}/extensions/${ext_id}"
  local crx_path="${USER_DATA_DIR}/extensions/${ext_id}.crx"
  
  log_message "Installing ${ext_name}..."
  
  # Create directory if it doesn't exist
  mkdir -p "${USER_DATA_DIR}/extensions"
  
  # Download the extension
  if download_file "$crx_url" "$crx_path"; then
    chmod 644 "$crx_path"
    
    # Unpack the CRX file
    mkdir -p "$ext_dir"
    unzip -o "$crx_path" -d "$ext_dir" >/dev/null 2>&1
    
    # Add to extension settings policy
    update_extension_settings "$ext_id" "$ext_name"
    
    log_message "${ext_name} installed successfully"
    return 0
  else
    log_error "Failed to download ${ext_name}"
    return 1
  fi
}

# Function to update extension settings policy
update_extension_settings() {
  local ext_id="$1"
  local ext_name="$2"
  local policy_file="${POLICY_DIR}/extension_settings.json"
  
  # Create or update the extension settings policy
  if [[ -f "$policy_file" ]]; then
    # Policy file exists, add this extension to it
    local temp_file="${policy_file}.tmp"
    jq ".ExtensionSettings[\"${ext_id}\"] = {\"installation_mode\": \"normal_installed\", \"update_url\": \"https://clients2.google.com/service/update2/crx\"}" "$policy_file" > "$temp_file"
    mv "$temp_file" "$policy_file"
  else
    # Create new policy file
    cat > "$policy_file" << EOF
{
  "ExtensionSettings": {
    "${ext_id}": {
      "installation_mode": "normal_installed",
      "update_url": "https://clients2.google.com/service/update2/crx"
    }
  }
}
EOF
  fi
  
  chmod 644 "$policy_file"
}

# Function to update launch agent with extension paths
update_launch_agent_with_extensions() {
  local launch_agent_file="${HOME}/Library/LaunchAgents/com.brave.extension.plist"
  local extensions_dir="${USER_DATA_DIR}/extensions"
  local dashboard_dir="${USER_DATA_DIR}/extensions/dashboard-extension"
  
  log_message "Updating launch agent with installed extensions..."
  
  # Build the load-extension parameter with all installed extensions
  local extension_paths=""
  
  # Add dashboard extension if it exists
  if [[ -d "$dashboard_dir" ]]; then
    extension_paths="$dashboard_dir"
  fi
  
  # Add other extensions if they exist
  if [[ -d "$extensions_dir" ]]; then
    for ext_dir in "$extensions_dir"/*; do
      if [[ -d "$ext_dir" && "$ext_dir" != "$dashboard_dir" ]]; then
        if [[ -n "$extension_paths" ]]; then
          extension_paths="${extension_paths},${ext_dir}"
        else
          extension_paths="${ext_dir}"
        fi
      fi
    done
  fi
  
  # Create or update the launch agent
  mkdir -p "${HOME}/Library/LaunchAgents"
  
  cat > "$launch_agent_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.brave.extension</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Brave Browser.app/Contents/MacOS/Brave Browser</string>
        <string>--load-extension=${extension_paths}</string>
        <string>--homepage=chrome://newtab</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
  
  chmod 644 "$launch_agent_file"
  
  # Update the AppleScript application
  local applescript_file="${HOME}/Applications/Brave Debloat.app"
  
  if [[ -d "$applescript_file" ]]; then
    cat > "${applescript_file}/Contents/MacOS/brave-debloat" << EOF
#!/bin/bash
open -a "Brave Browser" --args --load-extension="${extension_paths}" --homepage=chrome://newtab
EOF
    
    chmod +x "${applescript_file}/Contents/MacOS/brave-debloat"
  fi
  
  log_message "Launch agent and application updated with all installed extensions"
}

# Function to revert all changes
revert_all_changes() {
  log_message "Reverting all changes made by the script..."
  
  # Remove policy files
  if [[ -d "${POLICY_DIR}" ]]; then
    rm -f "${POLICY_DIR}"/*.json
    log_message "Removed policy files"
  fi
  
  # Remove launch agent
  local launch_agent_file="${HOME}/Library/LaunchAgents/com.brave.extension.plist"
  if [[ -f "$launch_agent_file" ]]; then
    rm -f "$launch_agent_file"
    log_message "Removed launch agent"
  fi
  
  # Remove AppleScript application
  local applescript_file="${HOME}/Applications/Brave Debloat.app"
  if [[ -d "$applescript_file" ]]; then
    rm -rf "$applescript_file"
    log_message "Removed Brave Debloat application"
  fi
  
  # Remove downloaded extensions
  if [[ -d "${USER_DATA_DIR}/extensions" ]]; then
    rm -rf "${USER_DATA_DIR}/extensions"
    log_message "Removed extensions"
  fi
  
  log_message "All changes have been reverted. Please restart Brave browser."
  log_message "Note: Any extensions you installed through the browser will remain."
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
    echo "6. Kagi (excellent engine
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
        if [[ -f "${LOCAL_STATE}" ]]; then
          jq 'del(.browser.enabled_labs_experiments[] | select(. == "brave-adblock-experimental-list-default@1"))' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
          mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
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
        
        log_message "Advanced Ad Blocking has been ENABLED"
      fi
    fi
    log_message "Please COMPLETELY QUIT Brave browser and restart for changes to take effect"
    log_message "After restart, check brave://components/ and update 'Brave Ad Block Updater' if needed"
  else
    log_error "Preferences file not found"
  fi
}

# Function to install recommended extensions
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
    local crx_url=$(echo "$ext_line" | cut -d'|' -f5)
    
    # Mark recommended extensions with an asterisk
    local mark=""
    if [[ "$recommended" == "true" ]]; then
      mark="*"
    fi
    
    printf "%2d. %-25s - %s %s\n" "$i" "$name" "$description" "$mark"
    extension_map["$i"]="$id|$name|$crx_url"
    ((i++))
  done < <(jq -r '.categories | to_entries[] | .value[] | [.id, .name, .description, (.recommended|tostring), .crx_url] | join("|")' "$temp_file")
  
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
      local crx_url=$(echo "$ext_line" | cut -d'|' -f3)
      selected_exts+=("$id|$name|$crx_url")
    done < <(jq -r '.recommended_ids[] as $id | .categories[][] | select(.id == $id) | [$id, .name, .crx_url] | join("|")' "$temp_file")
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

  # Install selected extensions
  if [ ${#selected_exts[@]} -gt 0 ]; then
    log_message "Installing selected extensions..."
    
    for ext in "${selected_exts[@]}"; do
      IFS='|' read -r id name crx_url <<< "$ext"
      install_extension_from_crx "$id" "$name" "$crx_url"
    done
    
    # Update launch agent with all extensions
    update_launch_agent_with_extensions
    
    log_message "All extensions installed. Please restart Brave browser for changes to take effect."
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

  echo "A script to debloat Brave browser and apply optimizations for macOS..."
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
  echo "14. Install Dashboard Customizer Extension"
  echo "    Replaces Brave's dashboard with a clean, black background and clock"
  echo
  echo "15. Revert All Changes"
  echo "    Removes all changes made by this script"
  echo
  echo "16. Exit"
  echo
  echo "You can select multiple options by entering numbers separated by spaces (e.g., 4 5 8)"
  echo "Note: Options 1, 2, and 15 cannot be combined with other options"
  echo
}

# Main function
main() {
  check_brave_installation
  
  while true; do
    show_menu
    
    read -p "Enter your choice(s) [1-16]: " choices
    
    # Convert input to array
    IFS=' ' read -ra selected_options <<< "$choices"
    
    # Check for exclusive options (1, 2, and 15)
    local has_exclusive=0
    for choice in "${selected_options[@]}"; do
      if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "15" ]]; then
        has_exclusive=1
        break
      fi
    done
    
    if [[ $has_exclusive -eq 1 && ${#selected_options[@]} -gt 1 ]]; then
      log_error "Options 1, 2, and 15 cannot be combined with other options"
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
          install_brave
          apply_default_optimizations
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
          install_dashboard_customizer
          sleep 2.5
          ;;
        15)
          read -p "Are you sure you want to revert all changes? (y/n): " confirm
          if [[ "$confirm" =~ ^[Yy]$ ]]; then
            revert_all_changes
          fi
          sleep 2.5
          ;;
        16)
          log_message "Exiting...
Thank you for using Brave debloat for macOS, lets make Brave great again."
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
  echo "Install with Homebrew: brew install jq"
  echo "Or visit: https://stedolan.github.io/jq/download/"
  exit 1
fi

# Run main script
main
