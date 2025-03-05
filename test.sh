#!/bin/bash

# Set strict mode
set -euo pipefail
[[ "${TRACE-0}" == "1" ]] && set -o xtrace

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

# Logging functions
log_message() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

# Script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# GitHub repository base URL (used as fallback)
readonly GITHUB_BASE="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main"

get_file() {
  local file_path="$1" output="$2" github_path="$3"
  if [[ -f "${SCRIPT_DIR}/${file_path}" ]]; then
    cp "${SCRIPT_DIR}/${file_path}" "$output"
  elif command -v curl &> /dev/null; then
    curl -s "${GITHUB_BASE}/${github_path}" -o "$output"
  elif command -v wget &> /dev/null; then
    wget -q "${GITHUB_BASE}/${github_path}" -O "$output"
  else
    log_error "Neither curl nor wget is installed. Please install one of them."
    return 1
  fi
  if [[ ! -s "$output" ]]; then
    log_error "Failed to get $file_path"
    return 1
  fi
  return 0
}

install_jq() {
  log_message "Attempting to install jq..."
  if [[ -f /etc/nixos/configuration.nix ]]; then
    nix-env -iA nixpkgs.jq
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y jq
  elif command -v dnf &> /dev/null; then
    sudo dnf install -y jq
  elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm jq
  elif command -v zypper &> /dev/null; then
    sudo zypper install -y jq
  else
    log_error "Unable to install jq automatically. Please install it manually."
    return 1
  fi

  if command -v jq &> /dev/null; then
    log_message "jq installed successfully."
  else
    log_error "Failed to install jq."
    return 1
  fi
}


install_brave_variant() {
  local variant="$1"
  local script_path="brave_install/install_brave_${variant}.sh"
  local script_url="${GITHUB_BASE}/${script_path}"
  
  local temp_script
  temp_script=$(mktemp)
  if [[ -f "${SCRIPT_DIR}/${script_path}" ]]; then
    cp "${SCRIPT_DIR}/${script_path}" "$temp_script"
  else
    get_file "$script_path" "$temp_script" "$script_path" || return 1
  fi
  
  chmod +x "$temp_script"
  "$temp_script"
  local result=$?
  rm "$temp_script"
  
  if command -v brave-browser &> /dev/null || command -v brave &> /dev/null || command -v brave-browser-beta &> /dev/null || command -v brave-browser-nightly &> /dev/null; then
    log_message "Brave Browser (${variant}) installed successfully."
    return 0
  fi
  
  if [[ "$variant" == "stable" ]]; then
    log_message "Standard installation methods failed. Trying Brave's official install script..."
    curl -fsS https://dl.brave.com/install.sh | sh
    
    if command -v brave-browser &> /dev/null || command -v brave &> /dev/null; then
      log_message "Brave Browser (stable) installed successfully using official script."
      return 0
    else
      log_error "All installation methods failed."
      return 1
    fi
  else
    log_error "Installation of Brave Browser (${variant}) failed. No fallback available for non-stable variants."
    return 1
  fi
}

create_brave_wrapper() {
    log_message "Creating Brave wrapper script..."
    local wrapper_path="/usr/local/bin/brave-debloat-wrapper"
    cat > "$wrapper_path" << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'
log_message() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
if command -v flatpak &> /dev/null && flatpak list | grep -q com.brave.Browser; then
    BRAVE_EXEC="flatpak run com.brave.Browser"
else
    BRAVE_EXEC=$(command -v brave-browser || command -v brave || command -v brave-browser-stable)
fi
EXTENSIONS_DIR="/usr/share/brave/extensions"
THEMES_DIR="/usr/share/brave/themes"
DASHBOARD_DIR="/usr/share/brave/extensions/dashboard-customizer"
EXTENSION_ARGS=""
[ -d "$DASHBOARD_DIR" ] && { EXTENSION_ARGS="--load-extension=${DASHBOARD_DIR}"; log_message "Dashboard Customizer installed"; }
for ext_dir in "$EXTENSIONS_DIR"/* "$THEMES_DIR"/*; do
    [ -d "$ext_dir" ] && [ "$ext_dir" != "$DASHBOARD_DIR" ] && ! [[ "$(basename "$ext_dir")" =~ ^(cjpalhdlnbpafiamejdnhcphjbkeiagm|eimadpbcbfnmbkopoojfekhnkhdbieeh|annfbnbieaamhaimclajlajpijgkdblo)$ ]] && EXTENSION_ARGS="${EXTENSION_ARGS:+$EXTENSION_ARGS,}${ext_dir}"
done
log_message "Launching Brave with managed extensions"
exec "$BRAVE_EXEC" $EXTENSION_ARGS --homepage=chrome://newtab "$@"
EOF
    chmod +x "$wrapper_path"
    log_message "Wrapper script created at $wrapper_path"
}

locate_brave_files() {
  log_message "Locating Brave browser..."
  echo "DEBUG: PATH=$PATH" >&2
  local profile_path=""

  # 1. Check for custom profile path in command line arguments
  if pgrep -f "brave.*--user-data-dir=([^ ]+)" > /dev/null; then
    profile_path=$(pgrep -f "brave.*--user-data-dir=([^ ]+)" -o | head -n 1 | grep -o "--user-data-dir=[^ ]+" | cut -d "=" -f 2)
    log_message "Custom profile path found in command line arguments: $profile_path"
  fi

  if command -v flatpak &> /dev/null; then
    BRAVE_FLATPAK=$(flatpak list --app | grep com.brave.Browser || true)
    if [[ -n "${BRAVE_FLATPAK}" ]]; then
      log_message "Flatpak Brave installation detected"
      BRAVE_EXEC="flatpak run com.brave.Browser"
      PREFERENCES_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default"
      POLICY_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/policies/managed"
      IS_FLATPAK=true
    fi
  fi

  if [[ -z "${BRAVE_EXEC-}" ]]; then
    BRAVE_EXEC="$(command -v brave || command -v brave-browser || command -v brave-browser-stable || echo '')"
    if [[ -z "${BRAVE_EXEC}" ]]; then
      log_message "Brave browser not found. Would you like to install it? (y/n)"
      read -t 10 -r install_choice || { log_error "No input, exiting"; exit 1; }
      if [[ "${install_choice}" =~ ^[Yy]$ ]]; then
        install_brave_variant "stable"
        BRAVE_EXEC="$(command -v brave-browser || command -v brave || command -v brave-browser-stable || echo '')"
        [[ -z "${BRAVE_EXEC}" ]] && { log_error "Installation failed"; exit 1; }
        log_message "Brave browser installed successfully."
      else
        log_error "Brave browser is required for this script"
        exit 1
      fi
    fi

    # 2. Determine PREFERENCES_DIR based on profile_path or default location
    if [[ -n "$profile_path" ]]; then
      PREFERENCES_DIR="${profile_path}/Default"
    else
      PREFERENCES_DIR="${HOME}/.config/BraveSoftware/Brave-Browser/Default"
    fi

    POLICY_DIR="/etc/brave/policies/managed"
    IS_FLATPAK=false
  fi

  mkdir -p "${POLICY_DIR}" "/usr/share/brave" "${PREFERENCES_DIR}"
  readonly BRAVE_PREFS="${PREFERENCES_DIR}/Preferences"
  log_message "Brave executable: ${BRAVE_EXEC}"
  log_message "Policy directory: ${POLICY_DIR}"
  log_message "Preferences directory: ${PREFERENCES_DIR}"
}

update_desktop_with_extensions() {
  local desktop_file="/usr/share/applications/brave-browser.desktop"
  if [[ -f "$desktop_file" ]]; then
    sed -i 's/^Exec=brave/Exec=brave --load-extension=\/usr\/share\/brave\/extensions\/*/' "$desktop_file"
    log_message "Updated desktop entry to load extensions"
  else
    log_error "Desktop entry file not found"
  fi
}


create_brave_wrapper() {
    log_message "Creating Brave wrapper script..."
    local wrapper_path="/usr/local/bin/brave-debloat-wrapper"
    cat > "$wrapper_path" << 'EOF'
#!/bin/bash
GREEN='\033[0;32m'
NC='\033[0m'
log_message() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
if command -v flatpak &> /dev/null && flatpak list | grep -q com.brave.Browser; then
    BRAVE_EXEC="flatpak run com.brave.Browser"
else
    BRAVE_EXEC=$(command -v brave-browser || command -v brave || command -v brave-browser-stable)
fi
EXTENSIONS_DIR="/usr/share/brave/extensions"
THEMES_DIR="/usr/share/brave/themes"
DASHBOARD_DIR="/usr/share/brave/extensions/dashboard-customizer"
EXTENSION_ARGS=""
[ -d "$DASHBOARD_DIR" ] && { EXTENSION_ARGS="--load-extension=${DASHBOARD_DIR}"; log_message "Dashboard Customizer installed"; }
for ext_dir in "$EXTENSIONS_DIR"/* "$THEMES_DIR"/*; do
    [ -d "$ext_dir" ] && [ "$ext_dir" != "$DASHBOARD_DIR" ] && ! [[ "$(basename "$ext_dir")" =~ ^(cjpalhdlnbpafiamejdnhcphjbkeiagm|eimadpbcbfnmbkopoojfekhnkhdbieeh|annfbnbieaamhaimclajlajpijgkdblo)$ ]] && EXTENSION_ARGS="${EXTENSION_ARGS:+$EXTENSION_ARGS,}${ext_dir}"
done
log_message "Launching Brave with managed extensions"
exec "$BRAVE_EXEC" $EXTENSION_ARGS --homepage=chrome://newtab "$@"
EOF
    chmod +x "$wrapper_path"
    log_message "Wrapper script created at $wrapper_path"
}
apply_policy() {
    local policy_name="$1"
    local policy_file="${POLICY_DIR}/${policy_name}.json"
    local policy_path="policies/${policy_name}.json"
    
    log_message "Applying ${policy_name} policy..."
    if [[ -f "${SCRIPT_DIR}/${policy_path}" ]]; then
        cp "${SCRIPT_DIR}/${policy_path}" "$policy_file"
    else
        get_file "$policy_path" "$policy_file" "$policy_path" || return 1
    fi
    
    chmod 644 "$policy_file"
    log_message "${policy_name} policy applied successfully"
    return 0
}

install_extension_from_crx() {
  local ext_id="$1" ext_name="$2"
  local ext_dir="/usr/share/brave/extensions/${ext_id}"
  local crx_path="/usr/share/brave/extensions/${ext_id}.crx"
  local local_crx="./extensions/${ext_id}.crx"
  [ -d "$ext_dir" ] && [ -f "$ext_dir/manifest.json" ] && { log_message "$ext_name already installed"; return 0; }
  log_message "Cleaning up $ext_name..."
  rm -rf "$ext_dir"
  log_message "Installing $ext_name..."
  mkdir -p "/usr/share/brave/extensions"
  if [ -f "$local_crx" ]; then
    log_message "Copying local $local_crx"
    cp "$local_crx" "$crx_path" || { log_error "Copy failed"; return 1; }
  else
    log_error "Local CRX $local_crx not found in ./extensions/"
    return 1
  fi
  chmod 644 "$crx_path"
  log_message "Unzipping $crx_path (size: $(du -h "$crx_path" | cut -f1))"
  unzip -o "$crx_path" -d "$ext_dir" >/dev/null 2>&1 || true  # Ignore unzip exit code
  rm -rf "$ext_dir/_metadata"
  [ -f "$ext_dir/manifest.json" ] || { log_error "Unzip failed—no manifest"; ls -l "$ext_dir"; return 1; }
  update_extension_settings "$ext_id" "$ext_name"
  log_message "$ext_name installed"
}

update_extension_settings() {
    local ext_id="$1" ext_name="$2"
    local policy_file="${POLICY_DIR}/extension_settings.json"
    if [ -f "$policy_file" ]; then
        jq ".ExtensionSettings[\"${ext_id}\"] = {\"installation_mode\": \"normal_installed\", \"update_url\": \"https://clients2.google.com/service/update2/crx\"}" "$policy_file" > "$policy_file.tmp"
        mv "$policy_file.tmp" "$policy_file"
    else
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
create_desktop_entry() {
  log_message "Creating desktop entry for Brave Debloat..."
  
  create_brave_wrapper
  
  local icon_path="brave-browser"
  local desktop_file="/usr/share/applications/brave-debloat.desktop"
  
cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Name=Brave Debloat
GenericName=Web Browser
Comment=Debloated and optimized Brave browser
Exec=/usr/local/bin/brave-debloat-wrapper %U
Icon=${icon_path}
Type=Application
Categories=Network;WebBrowser;
Terminal=false
StartupNotify=true
MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=/usr/local/bin/brave-debloat-wrapper

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=/usr/local/bin/brave-debloat-wrapper --incognito
EOF

  chmod 644 "$desktop_file"
  
  command -v update-desktop-database &> /dev/null && update-desktop-database
  command -v gtk-update-icon-cache &> /dev/null && gtk-update-icon-cache -f -t /usr/share/icons/hicolor
  
  log_message "Desktop entry created successfully with wrapper script"
  return 0
}

install_theme() {
  local theme_id="$1" theme_name="$2"
  local theme_dir="/usr/share/brave/themes/${theme_id}"
  local crx_path="/usr/share/brave/themes/${theme_id}.crx"
  local local_crx="./extensions/themes/${theme_id}.crx"
  log_message "Installing theme: $theme_name..."

  [ "$theme_id" = "brave_dark_mode" ] && { set_brave_dark_mode; return 0; }
  [ -d "$theme_dir" ] && [ ! -f "$theme_dir/manifest.json" ] && { log_message "Theme $theme_name already installed"; return 0; }

  log_message "Cleaning up $theme_name..."
  rm -rf "$theme_dir"
  [ -f "${POLICY_DIR}/dark_mode.json" ] && { log_message "Disabling dark mode for theme"; rm -f "${POLICY_DIR}/dark_mode.json" "/tmp/brave_debloat_dark_mode"; }

  mkdir -p "/usr/share/brave/themes"
  if [ -f "$local_crx" ]; then
    log_message "Copying local $local_crx"
    cp "$local_crx" "$crx_path" || { log_error "Copy failed"; return 1; }
  else
    log_error "Local CRX $local_crx not found in ./extensions/themes/"
    return 1
  fi

  chmod 644 "$crx_path"
  log_message "Unzipping $crx_path (size: $(du -h "$crx_path" | cut -f1))"
  unzip -o "$crx_path" -d "$theme_dir" >/dev/null 2>&1 || true # Ignore unzip exit code
  rm -rf "$theme_dir/_metadata"
  [ -f "$theme_dir/manifest.json" ] || { log_error "Unzip failed—no manifest"; ls -l "$theme_dir"; return 1; }

  update_extension_settings "$theme_id" "$theme_name"
  update_desktop_with_extensions
  log_message "Theme $theme_name activated"
  pkill -9 -f "brave.*" || true
  log_message "Brave restarted for theme"
}

select_theme() {
  log_message "Loading available themes from local consolidated_extensions.json..."
  local extensions_json="${SCRIPT_DIR}/policies/consolidated_extensions.json" # Path to your local consolidated_extensions.json file

  if [ ! -f "$extensions_json" ]; then
    log_error "Local consolidated_extensions.json file not found: $extensions_json"
    return 1
  fi

  local theme_count=$(jq '.categories.themes | length' "$extensions_json")
  [ "$theme_count" -eq 0 ] && { log_error "No themes found in $extensions_json"; return 1; }

  echo -e "\n=== Available Themes ==="
  local i=1
  declare -A theme_map
  while read -r id && read -r name && read -r description; do
    printf "%2d. %-35s - %s\n" "$i" "$name" "$description"
    theme_map["$i"]="$id|$name"
    ((i++))
  done < <(jq -r '.categories.themes[] | (.id, .name, .description // "No description")' "$extensions_json")

  echo -e "\nSelect a theme to install (1-$((i-1))): "
  read theme_choice
  if [ -n "${theme_map[$theme_choice]}" ]; then
    IFS='|' read -r id name <<< "${theme_map[$theme_choice]}"
    install_theme "$id" "$name" #Removed the crx_url as it is not used
  else
    log_error "Invalid selection: $theme_choice"
  fi
}
toggle_brave_sync() {
  local policy_file="${POLICY_DIR}/brave_sync.json"

  if [[ -f "$policy_file" ]]; then
    # Read current sync status
    local sync_status
    sync_status=$(jq '.SyncDisabled' "$policy_file")

    if [[ "$sync_status" == "false" ]]; then
      log_message "Brave Sync is currently ENABLED"
      read -p "Would you like to disable it? (y/n): " disable_choice
      if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
        # Disable sync by updating the JSON file
        echo '{"SyncDisabled": true}' > "$policy_file"
        chmod 644 "$policy_file"
        log_message "Brave Sync disabled"
      else
        log_message "Brave Sync remains enabled"
      fi
    else
      log_message "Brave Sync is currently DISABLED"
      read -p "Would you like to enable it? (y/n): " enable_choice
      if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
        # Enable sync by updating the JSON file
        echo '{"SyncDisabled": false}' > "$policy_file"
        chmod 644 "$policy_file"
        log_message "Brave Sync enabled"
      else
        log_message "Brave Sync remains disabled"
      fi
    fi
  else
    # If policy file does not exist, create it and enable sync by default
    echo '{"SyncDisabled": false}' > "$policy_file"
    chmod 644 "$policy_file"
    log_message "Brave Sync enabled (new policy created)"
  fi
}

toggle_brave_shields() {
  # Get the current user's home directory
  export HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

  local policy_file="${POLICY_DIR}/brave_shields.json"
  local user_policy_dir="${HOME}/.config/BraveSoftware/Brave-Browser/policies/managed" # Adjust path if needed
  local local_state="${HOME}/.config/BraveSoftware/Brave-Browser/Local State" # Corrected Local State path

  set -x # Enable tracing

  # 1. Apply Policy (if not already present)
  if [ ! -f "$policy_file" ]; then
    log_message "brave_shields.json does not exist, creating..."
    cat > "$policy_file" << EOF
{
  "ShieldsAdvancedControlsEnabled": true,
  "BlockAdsAndTracking": 2,              /* Aggressive */
  "HTTPSUpgradesEnabled": true,             /* Strict */
  "BlockScriptsEnabled": true,
  "BlockThirdPartyCookiesEnabled": true,
  "FingerprintingProtectionLevel": 2,    /* Strict */
  "PreventFingerprintingViaLanguage": true,
  "AutoRedirectAMPPagesEnabled": true,
  "AutoRedirectTrackingURLsEnabled": true
}
EOF
    chmod 644 "$policy_file"
    log_message "Brave Shields policy configured (brave_shields.json)"

    # Copy to user-level policy directory (if it exists)
    if [[ -d "$user_policy_dir" ]]; then
      log_message "User policy directory exists, copying policy..."
      mkdir -p "${user_policy_dir}"
      cp "$policy_file" "${user_policy_dir}/brave_shields.json"
      chmod 644 "${user_policy_dir}/brave_shields.json"
      log_message "Copied policy to user-level policy directory"
    else
      log_message "User policy directory does not exist, skipping copy."
    fi
  else
    log_message "brave_shields.json already exists, skipping creation."
  fi

  # 2. Modify Local State (Directly)
  log_message "local state ${local_state}"
  if [ -e "${local_state}" ]; then
    log_message "DEBUG: Local State exists (using -e)!"
  else
    log_message "DEBUG: Local State DOES NOT exist (using -e)!"
  fi

  if [[ -f "$local_state" ]]; then
    log_message "Local State file exists, attempting to modify for stricter Shields..."

    # Create a backup of the Local State file before modification
    cp "$local_state" "${local_state}.before_jq"

    # Construct the jq command
    local jq_command='.browser = (.browser // {}) | .browser.brave_shields = {"trackers_blocking_level": 2, "https_only_mode_enabled": true, "cookie_blocking_level": 2, "fingerprinting_blocking_enabled": true, "block_scripts_enabled": true}'
    log_message "Executing jq command: jq '$jq_command' \"$local_state\""

    # Set brave_shields settings (adjust keys as needed)
    jq "$jq_command" "$local_state" > "${local_state}.tmp" 2>&1 # Capture all output

    local jq_result=$?
    log_message "jq command exited with status: $jq_result"

    if [ $jq_result -eq 0 ]; then
      mv "${local_state}.tmp" "$local_state"
      log_message "Local State modified successfully for stricter Shields"

      # Create a backup of the Local State file after modification
      cp "$local_state" "${local_state}.after_jq"

    else
      log_error "Failed to modify Local State (check jq and key names). jq output:"
      cat "${local_state}.tmp" #Show the contents of the temp file, helpful if jq wrote something there
    fi
  else
    log_error "Local State file not found!"
  fi

  # 3. Forcefully kill brave processes
  sleep 1 # Give Brave time to see the policy
  for i in $(seq 3); do # Try 3 times - be aggressive
    pkill -9 -f 'brave.*' || true
    pkill -9 brave-browser || true #Specific kill
    sleep 0.2 #Shorter delay between kills
    if ! pgrep -f "brave.*"; then
      break # All processes are gone
    fi
  done

  # 4. Clear Brave's cache (very important)
  rm -rf "${HOME}/.cache/BraveSoftware/Brave-Browser/*"

  sleep 1 # Give the system time to kill the processes
  log_message "Brave restarted to apply Shields settings"

  set +x # Disable tracing
}

toggle_custom_scriptlets() {
  local policy_file="${POLICY_DIR}/custom_scriptlets.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Custom scriptlets are currently ENABLED"
    read -p "Would you like to disable them? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Custom scriptlets disabled"
      log_message "Brave Sync disabled"
    else
      log_message "Brave Sync remains enabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "SyncDisabled": false
}
EOF
    chmod 644 "$policy_file"
    log_message "Brave Sync enabled"
  fi
}
toggle_hardware_acceleration() {
  local policy_file="${POLICY_DIR}/hardware_acceleration.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Hardware acceleration is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      cat > "${policy_file}" << EOF
{
  "HardwareAccelerationModeEnabled": false
}
EOF
      chmod 644 "${policy_file}"
      log_message "Hardware acceleration disabled"
    else
      log_message "Hardware acceleration remains enabled"
    fi
  else
    cat > "${policy_file}" << EOF
{
  "HardwareAccelerationModeEnabled": true
}
EOF
    chmod 644 "${policy_file}"
    log_message "Hardware acceleration enabled"
  fi
}

toggle_analytics() {
  local policy_file="${POLICY_DIR}/analytics.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Analytics and data collection are currently DISABLED"
    read -p "Would you like to enable them? (y/n): " enable_choice
    if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Analytics and data collection enabled"
    else
      log_message "Analytics and data collection remain disabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "MetricsReportingEnabled": false,
  "CloudReportingEnabled": false,
  "SafeBrowsingExtendedReportingEnabled": false,
  "AutomaticallySendAnalytics": false,
  "DnsOverHttpsMode": "automatic"
}
EOF
    chmod 644 "$policy_file"
    log_message "Analytics and data collection disabled"
  fi
}

toggle_auto_clear_data() {
  local policy_file="${POLICY_DIR}/auto_clear_data.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Auto Clear Browsing Data on Exit is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Auto Clear Browsing Data on Exit disabled"
    else
      log_message "Auto Clear Browsing Data on Exit remains enabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "ClearBrowsingDataOnExitList": [
    "browsing_history",
    "download_history",
    "cookies_and_other_site_data",
    "cached_images_and_files"
  ]
}
EOF
    chmod 644 "$policy_file"
    log_message "Auto Clear Browsing Data on Exit enabled"
  fi
}
toggle_background_running() {
  local policy_file="${POLICY_DIR}/background_mode.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Background running is currently DISABLED"
    read -p "Would you like to enable it? (y/n): " enable_choice
    if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Background running enabled"
    else
      log_message "Background running remains disabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "BackgroundModeEnabled": false
}
EOF
    chmod 644 "$policy_file"
    log_message "Background running disabled"
    log_message "WARNING: Disabling background running may affect some browser functionality"
  fi
}

toggle_memory_saver() {
  local policy_file="${POLICY_DIR}/memory_saver.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Memory Saver is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Memory Saver disabled"
    else
      log_message "Memory Saver remains enabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "MemorySaverEnabled": true
}
EOF
    chmod 644 "$policy_file"
    log_message "Memory Saver enabled"
  fi
}

toggle_ui_improvements() {
  local policy_file="${POLICY_DIR}/ui_improvements.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "UI improvements are currently ENABLED"
    read -p "Would you like to disable them? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "UI improvements disabled"
    else
      log_message "UI improvements remain enabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "ShowFullURLsInAddressBar": true,
  "BookmarksBarEnabled": true,
  "WideAddressBarEnabled": true
}
EOF
    chmod 644 "$policy_file"
    log_message "UI improvements enabled (full URLs, wide address bar, bookmarks bar)"
  fi
}
modify_dashboard_preferences() {
    local preferences_file="${BRAVE_PREFS}"
    [ -f "$preferences_file" ] && jq -e '.brave.new_tab_page.show_clock == true and .brave.new_tab_page.show_shortcuts == false' "$preferences_file" >/dev/null 2>&1 && { log_message "Dashboard already customized"; return 0; }
    mkdir -p "$PREFERENCES_DIR"
    [ ! -f "$preferences_file" ] && { echo "{}" > "$preferences_file"; chmod 644 "$preferences_file"; }
    local temp_file="${preferences_file}.tmp"
    jq '.brave = (.brave // {}) | .brave.stats = (.brave.stats // {}) | .brave.stats.enabled = false | .brave.today = (.brave.today // {}) | .brave.today.should_show_brave_today_widget = false | .brave.new_tab_page = (.brave.new_tab_page // {}) | .brave.new_tab_page.show_clock = true | .brave.new_tab_page.show_search_widget = false | .brave.new_tab_page.show_branded_background_image = false | .brave.new_tab_page.show_cards = false | .brave.new_tab_page.show_background_image = false | .brave.new_tab_page.show_stats = false | .brave.new_tab_page.show_shortcuts = false' "$preferences_file" > "$temp_file"
    mv "$temp_file" "$preferences_file"
    chmod 644 "$preferences_file"
    log_message "Modified dashboard preferences - removed widgets, added clock"
}

toggle_brave_features() {
  local policy_file="${POLICY_DIR}/brave_features.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Brave Rewards/VPN/Wallet features are currently DISABLED"
    read -p "Would you like to enable them? (y/n): " enable_choice
    if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Brave Rewards/VPN/Wallet features enabled"
    else
      log_message "Brave Rewards/VPN/Wallet features remain disabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "BraveRewardsEnabled": false,
  "BraveVPNEnabled": false,
  "BraveWalletEnabled": false
}
EOF
    chmod 644 "$policy_file"
    log_message "Brave Rewards/VPN/Wallet features disabled"
  fi
}

toggle_experimental_adblock() {
  # Get the current user's home directory
  export HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

  local local_state="${HOME}/.config/BraveSoftware/Brave-Browser/Local State" # Corrected Local State path

  set -x # Enable tracing

  log_message "local state ${local_state}"
  if [ -e "${local_state}" ]; then
    log_message "DEBUG: Local State exists (using -e)!"
  else
    log_message "DEBUG: Local State DOES NOT exist (using -e)!"
  fi

  if [[ -f "$local_state" ]]; then
    if jq -e '.browser.enabled_labs_experiments' "$local_state" >/dev/null 2>&1; then
      log_message "Experimental ad blocking is currently ENABLED"
      read -p "Would you like to disable it? (y/n): " disable_choice
      if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
        jq 'del(.browser.enabled_labs_experiments[] | select(. == "brave-adblock-experimental-list-default@1"))' "$local_state" > "${local_state}.tmp"
        mv "${local_state}.tmp" "$local_state"
        log_message "Experimental ad blocking disabled"
      else
        log_message "Experimental ad blocking remains enabled"
      fi
    else
      log_message "Experimental ad blocking is currently DISABLED"
      read -p "Would you like to enable it? (y/n): " enable_choice
      if [[ "${enable_choice}" =~ ^[Yy]$ ]]; then
        jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "$local_state" > "${local_state}.tmp"
        mv "${local_state}.tmp" "$local_state"
        log_message "Experimental ad blocking enabled"
      else
        log_message "Experimental ad blocking remains disabled"
      fi
    fi
  else
    log_error "Local State file not found!"
  fi
  set +x # Disable tracing
}
install_recommended_extensions() {
  log_message "Loading recommended extensions..."
  local temp_file=$(mktemp)
  local extensions_json="${SCRIPT_DIR}/policies/consolidated_extensions.json"
  
  if [[ -f "$extensions_json" ]]; then
    cp "$extensions_json" "$temp_file"
  else
    get_file "policies/consolidated_extensions.json" "$temp_file" "policies/consolidated_extensions.json" || return 1
  fi
  
  local ext_count=$(jq '[.categories | to_entries[] | select(.key != "themes") | .value[]] | length' "$temp_file")
  if [ "$ext_count" -eq 0 ]; then
    log_error "No extensions found in the extensions data"
    rm "$temp_file"
    return 1
  fi
  
  echo -e "\n=== Recommended Extensions ==="
  local i=1
  declare -A ext_map
  local recommended_ids=$(jq -r '.recommended_ids[]' "$temp_file" | tr '\n' ' ')
  
  while read -r id && read -r name && read -r description && read -r crx_url; do
    local mark=""
    echo "$recommended_ids" | grep -q "$id" && mark="*"
    printf "%2d. %-35s - %s %s\n" "$i" "$name" "$description" "$mark"
    ext_map["$i"]="$id|$name|$crx_url"
    ((i++))
  done < <(jq -r '.categories | to_entries[] | select(.key != "themes") | .value[] | (.id, .name, .description // "No description", .crx_url)' "$temp_file")
  
  echo -e "\n* = Recommended extension"
  echo -e "Select extensions to install (e.g., '1 3 5' or 'all', '0' to exit): "
  read -r choices
  
  if [[ "$choices" == "0" ]]; then
    log_message "Exiting extension installer"
    rm "$temp_file"
    return 0
  elif [[ "$choices" == "all" ]]; then
    for key in "${!ext_map[@]}"; do
      IFS='|' read -r id name crx_url <<< "${ext_map[$key]}"
      install_extension_from_crx "$id" "$name" "$crx_url"
    done
  else
    IFS=' ' read -ra selected_options <<< "$choices"
    for choice in "${selected_options[@]}"; do
      if [[ -n "${ext_map[$choice]}" ]]; then
        IFS='|' read -r id name crx_url <<< "${ext_map[$choice]}"
        install_extension_from_crx "$id" "$name" "$crx_url"
      else
        log_error "Invalid selection: $choice"
      fi
    done
  fi
  
  rm "$temp_file"
  log_message "Extensions processed"
}

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
        case $search_choice in
            1)
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Brave",
  "DefaultSearchProviderSearchURL": "https://search.brave.com/search?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq '.default_search_provider_data = {"keyword": "brave", "name": "Brave", "search_url": "https://search.brave.com/search?q={searchTerms}"}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to Brave Search"
                break
                ;;
            2)
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "DuckDuckGo",
  "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq '.default_search_provider_data = {"keyword": "ddg", "name": "DuckDuckGo", "search_url": "https://duckduckgo.com/?q={searchTerms}"}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to DuckDuckGo"
                break
                ;;
            3)
                read -p "Enter your SearXNG instance URL (e.g., https://searxng.example.com): " searx_url
                [[ "$searx_url" =~ ^https?:// ]] || { log_error "Invalid URL format"; sleep 2; continue; }
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "SearXNG",
  "DefaultSearchProviderSearchURL": "${searx_url}/search?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq ".default_search_provider_data = {\"keyword\": \"searxng\", \"name\": \"SearXNG\", \"search_url\": \"${searx_url}/search?q={searchTerms}\"}" "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to SearXNG"
                break
                ;;
            4)
                read -p "Enter your Whoogle instance URL (e.g., https://whoogle.example.com): " whoogle_url
                [[ "$whoogle_url" =~ ^https?:// ]] || { log_error "Invalid URL format"; sleep 2; continue; }
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Whoogle",
  "DefaultSearchProviderSearchURL": "${whoogle_url}/search?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq ".default_search_provider_data = {\"keyword\": \"whoogle\", \"name\": \"Whoogle\", \"search_url\": \"${whoogle_url}/search?q={searchTerms}\"}" "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to Whoogle"
                break
                ;;
            5)
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Yandex",
  "DefaultSearchProviderSearchURL": "https://yandex.com/search/?text={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq '.default_search_provider_data = {"keyword": "yandex", "name": "Yandex", "search_url": "https://yandex.com/search/?text={searchTerms}"}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to Yandex"
                break
                ;;
            6)
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Kagi",
  "DefaultSearchProviderSearchURL": "https://kagi.com/search?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq '.default_search_provider_data = {"keyword": "kagi", "name": "Kagi", "search_url": "https://kagi.com/search?q={searchTerms}"}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to Kagi"
                break
                ;;
            7)
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Google",
  "DefaultSearchProviderSearchURL": "https://www.google.com/search?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq '.default_search_provider_data = {"keyword": "google", "name": "Google", "search_url": "https://www.google.com/search?q={searchTerms}"}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to Google"
                break
                ;;
            8)
                cat > "$policy_file" << EOF
{
  "DefaultSearchProviderEnabled": true,
  "DefaultSearchProviderName": "Bing",
  "DefaultSearchProviderSearchURL": "https://www.bing.com/search?q={searchTerms}"
}
EOF
                chmod 644 "$policy_file"
                jq '.default_search_provider_data = {"keyword": "bing", "name": "Bing", "search_url": "https://www.bing.com/search?q={searchTerms}"}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
                mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
                chmod 644 "$BRAVE_PREFS"
                log_message "Search engine set to Bing"
                break
                ;;
            9)
                log_message "Returning to main menu"
                return
                ;;
            *)
                log_error "Invalid option"
                sleep 2
                ;;
        esac
    done
    pkill -9 -f "brave.*" || true
    local secure_prefs="${HOME}/.config/BraveSoftware/Brave-Browser/Default/Secure Preferences"
    [ -f "$secure_prefs" ] && jq 'del(.extensions.settings[] | select(.search_provider)) | del(.omnibox)' "$secure_prefs" > "$secure_prefs.tmp" && mv "$secure_prefs.tmp" "$secure_prefs" && chmod 644 "$secure_prefs"
    rm -rf "${HOME}/.cache/BraveSoftware/Brave-Browser/*"
    log_message "Brave processes killed and caches cleared"
}
toggle_custom_scriptlets() {
  local policy_file="${POLICY_DIR}/custom_scriptlets.json"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Custom scriptlets are currently ENABLED"
    read -p "Would you like to disable them? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file"
      log_message "Custom scriptlets disabled"
    else
      log_message "Custom scriptlets remain enabled"
    fi
  else
    cat > "$policy_file" << EOF
{
  "EnableCustomScriptlets": true
}
EOF
    chmod 644 "$policy_file"
    log_message "Custom scriptlets enabled"
    log_message "WARNING: Only use custom scriptlets from trusted sources. Improper use can compromise your privacy and security."
    log_message "To use custom scriptlets, go to brave://settings/shields/filters, enable developer mode, and add new scriptlets."
  fi
}

install_dashboard_customizer() {
  local ext_id="dashboard-customizer" ext_name="Dashboard Customizer"
  local ext_dir="/usr/share/brave/extensions/${ext_id}"
  local crx_path="/usr/share/brave/extensions/${ext_id}.crx"
  local local_crx="${SCRIPT_DIR}/brave-dashboard-customizer/brave-dashboard-customizer.crx"
  log_message "Installing $ext_name..."
  [ -d "$ext_dir" ] && [ -f "$ext_dir/manifest.json" ] && { log_message "$ext_name already installed"; return 0; }
  log_message "Cleaning up $ext_name..."
  rm -rf "$ext_dir" "$crx_path"
  log_message "Installing $ext_name..."
  mkdir -p "/usr/share/brave/extensions"
  if [ -f "$local_crx" ]; then
    log_message "Copying local $local_crx"
    cp "$local_crx" "$crx_path" || { log_error "Copy failed"; return 1; }
  else
    log_error "Local CRX $local_crx not found—place it in ${SCRIPT_DIR}/brave-dashboard-customizer/"
    return 1
  fi
  chmod 644 "$crx_path"
  log_message "Unzipping $crx_path (size: $(du -h "$crx_path" | cut -f1))"
  unzip -o "$crx_path" -d "$ext_dir" >/dev/null 2>&1 || true  # Ignore unzip exit
  rm -rf "$ext_dir/_metadata"
  [ -f "$ext_dir/manifest.json" ] || { log_error "Unzip failed—no manifest"; ls -l "$ext_dir"; return 1; }
  log_message "$ext_name installed"
  local policy_file="${POLICY_DIR}/extension_settings.json"
  if [ -f "$policy_file" ]; then
    jq ".ExtensionSettings[\"${ext_id}\"] = {\"installation_mode\": \"normal_installed\", \"update_url\": \"https://clients2.google.com/service/update2/crx\", \"toolbar_pin\": \"force_pinned\"}" "$policy_file" > "$policy_file.tmp"
    mv "$policy_file.tmp" "$policy_file"
  else
    cat > "$policy_file" << EOF
{
  "ExtensionSettings": {
    "${ext_id}": {
      "installation_mode": "normal_installed",
      "update_url": "https://clients2.google.com/service/update2/crx",
      "toolbar_pin": "force_pinned"
    }
  }
}
EOF
  fi
  chmod 644 "$policy_file"
  mkdir -p "$PREFERENCES_DIR"
  [ ! -f "$BRAVE_PREFS" ] && { echo "{}" > "$BRAVE_PREFS"; chmod 644 "$BRAVE_PREFS"; }
  jq '.brave.new_tab_page = (.brave.new_tab_page // {}) | .brave.new_tab_page.show_background_image = false | .brave.new_tab_page.show_stats = false | .brave.new_tab_page.show_shortcuts = false | .brave.new_tab_page.show_branded_background_image = false | .brave.new_tab_page.show_cards = false | .brave.new_tab_page.show_search_widget = false | .brave.new_tab_page.show_clock = false | .brave.new_tab_page.show_brave_news = false | .brave.new_tab_page.show_together = false' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp" || { log_error "Failed to update Preferences"; cat "$BRAVE_PREFS.tmp"; return 1; }
  mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
  chmod 644 "$BRAVE_PREFS"
  log_message "Stripped Brave dashboard features"
  local desktop_file="/usr/share/applications/brave-debloat.desktop"
  [ ! -f "$desktop_file" ] && create_desktop_entry
  local brave_exec=$(grep "^Exec=" "$desktop_file" | head -1 | sed -E 's/Exec=([^ ]+).*/\1/')
  local temp_file=$(mktemp)
  while IFS= read -r line; do
    [ "$line" = "${line#Exec=}" ] || line="Exec=${brave_exec} --load-extension=${ext_dir} --homepage=chrome://newtab"
    echo "$line" >> "$temp_file"
  done < "$desktop_file"
  mv "$temp_file" "$desktop_file"
  chmod 644 "$desktop_file"
  log_message "Updated desktop entry for $ext_name"
  pkill -9 -f "brave.*" || true
  log_message "Brave processes killed—restart to see $ext_name"
}

toggle_policy() {
    local policy_name="$1"
    local policy_file="${POLICY_DIR}/${policy_name}.json"
    local feature_name="$2"
    if [ -f "$policy_file" ]; then
        log_message "$feature_name is currently ENABLED"
        read -p "Disable? (y/n): " disable_choice
        [[ "$disable_choice" =~ ^[Yy]$ ]] && { rm -f "$policy_file"; log_message "$feature_name disabled"; } || log_message "$feature_name remains enabled"
    else
        apply_policy "$policy_name"
        log_message "$feature_name enabled"
    fi
}

apply_default_optimizations() {
  log_message "Applying default optimizations..."
  apply_policy "brave_optimizations"
  apply_policy "adblock"
  apply_policy "privacy"
  apply_policy "ui"
  apply_policy "features"
  local shields_policy="${POLICY_DIR}/brave_shields.json"
  cat > "$shields_policy" << EOF
{
  "DefaultBraveShieldsEnabled": true,
  "BlockTrackers": "aggressive",
  "HTTPSUpgrades": "strict",
  "BlockScripts": "true",
  "BlockThirdPartyCookies": true,
  "BlockFingerprinting": "strict",
  "PreventFingerprintingViaLanguageSettings": true,
  "AutoRedirectAMPPages": true,
  "AutoRedirectTrackingURLs": true
}
EOF
  chmod 644 "$shields_policy"
  create_desktop_entry
  modify_dashboard_preferences
  log_message "Installing recommended extensions..."
  install_extension_from_crx "cjpalhdlnbpafiamejdnhcphjbkeiagm" "uBlock Origin" "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=91.0.4472.124&x=id%3Dcjpalhdlnbpafiamejdnhcphjbkeiagm%26uc"
  install_extension_from_crx "eimadpbcbfnmbkopoojfekhnkhdbieeh" "Dark Reader" "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=91.0.4472.124&x=id%3Deimadpbcbfnmbkopoojfekhnkhdbieeh%26uc"
  install_theme "annfbnbieaamhaimclajlajpijgkdblo" "Dark Theme for Google Chrome" "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=91.0.4472.124&x=id%3Dannfbnbieaamhaimclajlajpijgkdblo%26uc"
  update_desktop_with_extensions
  log_message "Default optimizations and stricter Brave Shields applied successfully"
  log_message "Please restart Brave browser for changes to take effect"
}

install_brave_and_optimize() {
  log_message "Installing Brave and applying optimizations..."
  install_brave_variant "stable"
  apply_default_optimizations
  log_message "Brave installed and optimized with stricter Shields settings"
}

revert_all_changes() {
  log_message "Reverting all changes made by this script..."
  
  if [[ "$IS_FLATPAK" == "true" ]]; then
    rm -rf "${POLICY_DIR}"/*
    rm -rf "${PREFERENCES_DIR}"
    flatpak override --user --reset com.brave.Browser
  elif [[ -f /etc/nixos/configuration.nix ]]; then
    log_message "NixOS detected. Please manually remove Brave configuration from your configuration.nix file and rebuild."
  else
    rm -rf "${POLICY_DIR}"/*
    rm -f "${BRAVE_PREFS}"
    rm -f "/usr/share/applications/brave-debloat.desktop"
    rm -f "/usr/local/bin/brave-debloat-wrapper"
    rm -rf /usr/share/brave/extensions/*
  fi
  
  log_message "All changes reverted, including stricter Brave Shields settings"
  log_message "Please restart Brave for changes to take effect"
}

set_brave_dark_mode() {
  local policy_file="${POLICY_DIR}/dark_mode.json"
  local dark_mode_flag="/tmp/brave_debloat_dark_mode"
  
  if [[ -f "$policy_file" ]]; then
    log_message "Dark mode is currently ENABLED"
    read -p "Would you like to disable it? (y/n): " disable_choice
    if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
      rm -f "$policy_file" "$dark_mode_flag"
      log_message "Dark mode disabled"
    else
      log_message "Dark mode remains enabled"
    fi
  else
    cat > "$policy_file" << EOF
{
    "NativeTheme": {
        "default_theme": "dark"
    }
}
EOF
    chmod 644 "$policy_file"
    touch "$dark_mode_flag"
    log_message "Dark mode enabled"
  fi
}

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
  echo "=== Brave Browser Optimization Menu ==="
  echo "1. Apply Default Optimizations (Recommended)"
  echo "2. Install Brave and Apply Customization"
  echo "3. Change Search Engine Preferences"
  echo "4. Toggle Brave Sync (Enable/Disable)"
  echo "5. Toggle Hardware Acceleration"
  echo "6. Disable Analytics & Data Collection"
  echo "7. Apply Stricter Brave Shields Configuration (NOT RECOMMENDED: TESTING)"
  echo "8. Toggle Auto Clear Browsing Data on Exit"
  echo "9. Disable Background Running (Warning: May cause instability)"
  echo "10. Toggle Memory Saver Mode for Tabs"
  echo "11. UI Improvements (Show Full URLs, Wide Address Bar, Bookmarks Bar)"
  echo "12. Dashboard Customization (Remove Widgets, Add Clock)"
  echo "13. Remove Brave Rewards/VPN/Wallet Features"
  echo "14. Toggle Experimental Ad Blocking (NOT RECOMMENDED: TESTING)"
  echo "15. Install Recommended Extensions (Adblockers, Utils, Password Wallets .)"
  echo "16. Install Dashboard Customizer Extension"
  echo "17. Enable Dark Mode for Brave Browser UI Themes" 
  echo "18. Install Browser Themes"
  echo "19. Enable Custom Scriptlets (Advanced)"
  echo "20. Revert All Changes Made by This Script"
  echo "21. Exit Script"
  echo
  echo "Select an option by entering its number:"
}

main() {
  if ! command -v jq &> /dev/null; then
    install_jq
  fi
  locate_brave_files
  while true; do
    show_menu
    read -p "> " choice
    case $choice in
      1) apply_default_optimizations; sleep 2.5;;
      2) install_brave_and_optimize; sleep 2.5;;
      3) set_search_engine; sleep 2.5;;
      4) toggle_brave_sync; sleep 2.5;;
      5) toggle_hardware_acceleration; sleep 2.5;;
      6) toggle_analytics; sleep 2.5;;
      7) toggle_brave_shields; sleep 2.5;;
      8) toggle_auto_clear_data; sleep 2.5;;
      9) toggle_background_running; sleep 2.5;;
      10) toggle_memory_saver; sleep 2.5;;
      11) toggle_ui_improvements; sleep 2.5;;
      12) modify_dashboard_preferences; sleep 2.5;;
      13) toggle_brave_features; sleep 2.5;;
      14) toggle_experimental_adblock; sleep 2.5;;
      15) install_recommended_extensions; sleep 2.5;;
      16) install_dashboard_customizer; sleep 2.5;;
      17) set_brave_dark_mode; sleep 2.5;;
      18) select_theme; sleep 2.5;;
      19) toggle_custom_scriptlets; sleep 2.5;;
      20) read -p "Revert all changes? (y/n): " confirm; [[ "$confirm" =~ ^[Yy]$ ]] && revert_all_changes; sleep 2.5;;
      21) log_message "Exiting..."; sleep 2.5; exit 0;;
      *) log_error "Invalid option: $choice"; sleep 2.5;;
    esac
    [ "${#choice}" -gt 0 ] && log_message "Option processed. Please restart Brave for changes to take effect." && sleep 2.5
  done
}

# Run the main function
main
