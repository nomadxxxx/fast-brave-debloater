#!/bin/bash

# Fast Brave Debloater for macOS
# Nomadxxxx - March 2025

echo "Script starting..."

# Check for root - sudo required for some operations
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo for system-wide changes"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# GitHub base URL
GITHUB_BASE="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main"

# Logging functions
log_message() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
log_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }

# Check dependencies
command -v jq >/dev/null 2>&1 || { log_error "jq required—install with 'brew install jq'"; exit 1; }
command -v curl >/dev/null 2>&1 || { log_error "curl required—install with 'brew install curl'"; exit 1; }
command -v plutil >/dev/null 2>&1 || { log_error "plutil required—should be built-in on macOS"; exit 1; }

# Paths
BRAVE_APP="/Applications/Brave Browser.app"
PREFS_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default"
POLICY_DIR="/Library/Managed Preferences/com.brave.Browser"
EXT_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Extensions"
THEMES_DIR="$EXT_DIR/themes"
DASHBOARD_DIR="$EXT_DIR/dashboard-customizer"
BRAVE_PREFS="$PREFS_DIR/Preferences"
LOCAL_STATE="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
WRAPPER_PATH="$HOME/bin/brave-debloat-wrapper"
APP_DIR="$HOME/Applications/Brave Debloat.app"

# Ensure dirs exist
mkdir -p "$PREFS_DIR" "$POLICY_DIR" "$EXT_DIR" "$THEMES_DIR" "$HOME/bin" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Download helper
download_file() {
  local url="$1" output="$2"
  curl -s "$url" -o "$output" || { log_error "Failed to download $url"; return 1; }
  [ -s "$output" ] || { log_error "Downloaded $output is empty"; return 1; }
  return 0
}

# Locate Brave
locate_brave() {
  log_message "Locating Brave Browser..."
  if [ ! -d "$BRAVE_APP" ]; then
    log_message "Brave not found. Install now? (y/n)"
    read -r choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
      install_brave_variant "stable"
    else
      log_error "Brave required—install manually and rerun"; exit 1
    fi
  fi
  BRAVE_EXEC="$BRAVE_APP/Contents/MacOS/Brave Browser"
  log_message "Brave found at: $BRAVE_EXEC"
}

# Install Brave variant
install_brave_variant() {
  local variant="$1"
  log_message "Installing Brave $variant via Homebrew..."
  case "$variant" in
    "stable") brew install --cask brave-browser ;;
    "beta") brew install --cask brave-browser-beta ;;
    "nightly") brew install --cask brave-browser-nightly ;;
    *) log_error "Invalid variant: $variant"; return 1 ;;
  esac || { log_error "Brew install failed for $variant"; return 1; }
  log_message "Brave $variant installed"
}

# Create wrapper script
create_wrapper() {
  log_message "Creating wrapper script..."
  cat > "$WRAPPER_PATH" << 'EOF'
#!/bin/bash
BRAVE_EXEC="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
EXT_DIR="$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Extensions"
DASHBOARD_DIR="$EXT_DIR/dashboard-customizer"
THEMES_DIR="$EXT_DIR/themes"

EXT_ARGS=""
[ -d "$DASHBOARD_DIR" ] && EXT_ARGS="--load-extension=$DASHBOARD_DIR"
for ext_dir in "$EXT_DIR"/* "$THEMES_DIR"/*; do
  [ -d "$ext_dir" ] && [[ "$(basename "$ext_dir")" != "dashboard-customizer" ]] && EXT_ARGS="$EXT_ARGS${EXT_ARGS:+,}$ext_dir"
done

DARK_MODE=""
[ -f "$HOME/.brave_debloat_dark_mode" ] && DARK_MODE="--force-dark-mode"

exec "$BRAVE_EXEC" $EXT_ARGS --homepage=chrome://newtab $DARK_MODE "$@"
EOF
  chmod +x "$WRAPPER_PATH"
  log_message "Wrapper created at $WRAPPER_PATH"
}

# Create app bundle
create_app_bundle() {
  log_message "Creating Brave Debloat app bundle..."
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
  cp "$BRAVE_APP/Contents/Resources/app.icns" "$APP_DIR/Contents/Resources/icon.icns" 2>/dev/null || log_message "Using default icon"
  cat > "$APP_DIR/Contents/MacOS/Brave Debloat" << 'EOF'
#!/bin/bash
"$HOME/bin/brave-debloat-wrapper" &
EOF
  chmod +x "$APP_DIR/Contents/MacOS/Brave Debloat"
  cat > "$APP_DIR/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Brave Debloat</string>
  <key>CFBundleIdentifier</key>
  <string>com.nomadxxxx.brave-debloat</string>
  <key>CFBundleName</key>
  <string>Brave Debloat</string>
  <key>CFBundleIconFile</key>
  <string>icon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
EOF
  log_message "App bundle created at $APP_DIR"
}

# Apply policy (JSON to plist)
apply_policy() {
  local name="$1" file="$POLICY_DIR/$name.plist"
  log_message "Applying $name policy..."
  local temp_json="/tmp/$name.json"
  download_file "$GITHUB_BASE/policies/$name.json" "$temp_json" || return 1
  plutil -convert xml1 "$temp_json" -o "$file" || { log_error "Failed to convert $name.json to plist"; return 1; }
  chmod 644 "$file"
  log_message "$name policy applied"
}

# Toggle policy
toggle_policy() {
  local name="$1" file="$POLICY_DIR/$name.plist" feature="$2"
  if [ -f "$file" ]; then
    log_message "$feature is ENABLED"
    read -p "Disable it? (y/n): " choice
    [[ "$choice" =~ ^[Yy]$ ]] && { rm -f "$file"; log_message "$feature disabled"; } || log_message "$feature remains enabled"
  else
    apply_policy "$name"
    log_message "$feature enabled"
  fi
}

# Install extension
install_extension() {
  local id="$1" name="$2" url="$3" dir="$EXT_DIR/$id"
  if [ -d "$dir" ] && [ ! -f "$dir/_metadata" ]; then
    log_message "$name already installed"
    return 0
  fi
  log_message "Installing $name..."
  local crx_path="$EXT_DIR/$id.crx"
  download_file "$url" "$crx_path" || return 1
  mkdir -p "$dir"
  unzip -o -q "$crx_path" -d "$dir" || { log_error "Failed to unzip $name"; return 1; }
  rm -rf "$dir/_metadata"
  [ -f "$dir/manifest.json" ] || { log_error "Manifest missing for $name"; return 1; }
  log_message "$name installed"
}

# Install theme
install_theme() {
  local id="$1" name="$2" url="$3" dir="$THEMES_DIR/$id"
  if [ -d "$dir" ] && [ ! -f "$dir/_metadata" ]; then
    log_message "$name already installed"
    return 0
  fi
  log_message "Installing theme: $name..."
  local crx_path="$THEMES_DIR/$id.crx"
  download_file "$url" "$crx_path" || return 1
  mkdir -p "$dir"
  unzip -o -q "$crx_path" -d "$dir" || { log_error "Failed to unzip $name"; return 1; }
  rm -rf "$dir/_metadata"
  [ -f "$dir/manifest.json" ] || { log_error "Manifest missing for $name"; return 1; }
  log_message "$name installed"
  [ -f "$HOME/.brave_debloat_dark_mode" ] && { rm -f "$HOME/.brave_debloat_dark_mode"; log_message "Disabled dark mode for theme"; }
}

# Default optimizations
apply_default_optimizations() {
  log_message "Applying default optimizations..."
  apply_policy "brave_optimizations"
  apply_policy "adblock"
  apply_policy "privacy"
  apply_policy "ui"
  apply_policy "features"
  create_app_bundle

  install_extension "cjpalhdlnbpafiamejdnhcphjbkeiagm" "uBlock Origin" "$GITHUB_BASE/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.crx"
  install_extension "eimadpbcbfnmbkopoojfekhnkhdbieeh" "Dark Reader" "$GITHUB_BASE/extensions/eimadpbcbfnmbkopoojfekhnkhdbieeh.crx"
  install_theme "annfbnbieaamhaimclajlajpijgkdblo" "Dark Theme for Google Chrome" "$GITHUB_BASE/extensions/themes/annfbnbieaamhaimclajlajpijgkdblo.crx"
  install_dashboard_customizer

  [ -f "$LOCAL_STATE" ] && jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "$LOCAL_STATE" > "$LOCAL_STATE.tmp" && mv "$LOCAL_STATE.tmp" "$LOCAL_STATE"
  log_message "Optimizations applied—restart Brave!"
}

# Install and optimize
install_brave_and_optimize() {
  log_message "Installing and optimizing Brave..."
  install_brave_variant "stable"
  apply_default_optimizations
}

# Search engine picker
set_search_engine() {
  while true; do
    clear
    echo "=== Search Engine Selection ==="
    echo "1. Brave Search"
    echo "2. DuckDuckGo"
    echo "3. SearXNG (self-hosted)"
    echo "4. Whoogle (self-hosted)"
    echo "5. Yandex"
    echo "6. Kagi"
    echo "7. Google"
    echo "8. Bing"
    echo "9. Back"
    read -p "Pick [1-9]: " choice
    
    local policy_file="$POLICY_DIR/search_provider.plist"
    case $choice in
      1) plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"Brave\",DefaultSearchProviderSearchURL=\"https://search.brave.com/search?q={searchTerms}\"}" ;;
      2) plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"DuckDuckGo\",DefaultSearchProviderSearchURL=\"https://duckduckgo.com/?q={searchTerms}\"}" ;;
      3) read -p "Enter SearXNG URL: " url; plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"SearXNG\",DefaultSearchProviderSearchURL=\"$url/search?q={searchTerms}\"}" ;;
      4) read -p "Enter Whoogle URL: " url; plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"Whoogle\",DefaultSearchProviderSearchURL=\"$url/search?q={searchTerms}\"}" ;;
      5) plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"Yandex\",DefaultSearchProviderSearchURL=\"https://yandex.com/search/?text={searchTerms}\"}" ;;
      6) plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"Kagi\",DefaultSearchProviderSearchURL=\"https://kagi.com/search?q={searchTerms}\"}" ;;
      7) plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"Google\",DefaultSearchProviderSearchURL=\"https://www.google.com/search?q={searchTerms}\"}" ;;
      8) plist="{DefaultSearchProviderEnabled=true,DefaultSearchProviderName=\"Bing\",DefaultSearchProviderSearchURL=\"https://www.bing.com/search?q={searchTerms}\"}" ;;
      9) return ;;
      *) log_error "Invalid choice"; sleep 2; continue ;;
    esac
    
    echo "$plist" | plutil -convert xml1 - -o "$policy_file"
    jq ".default_search_provider_data = {\"keyword\": \"$(echo $choice | cut -c1)\", \"name\": \"$(echo "$plist" | grep -o 'DefaultSearchProviderName="[^"]*"' | cut -d'"' -f2)\", \"search_url\": \"$(echo "$plist" | grep -o 'DefaultSearchProviderSearchURL="[^"]*"' | cut -d'"' -f2)\"}" "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
    mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
    log_message "Set search engine—restart Brave!"
    break
  done
  pkill -9 "Brave Browser"
}

# Toggles
toggle_hardware_acceleration() { toggle_policy "hardware" "Hardware Acceleration"; }
toggle_analytics() { toggle_policy "privacy" "Analytics & Data Collection"; }
toggle_memory_saver() { toggle_policy "memory_saver" "Memory Saver"; }
toggle_ui_improvements() { toggle_policy "ui" "UI Improvements"; }
toggle_brave_features() { toggle_policy "features" "Brave Rewards/VPN/Wallet"; }

modify_dashboard_preferences() {
  log_message "Customizing dashboard..."
  [ -f "$BRAVE_PREFS" ] || echo "{}" > "$BRAVE_PREFS"
  jq '.brave.new_tab_page = {show_clock: true, show_background_image: false, show_stats: false, show_shortcuts: false, show_branded_background_image: false, show_cards: false, show_search_widget: false}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
  mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
  log_message "Dashboard customized"
}

install_dashboard_customizer() {
  install_extension "dashboard-customizer" "Dashboard Customizer" "$GITHUB_BASE/brave-dashboard-customizer/brave-dashboard-customizer.crx"
  jq '.brave.new_tab_page = {show_background_image: false, show_stats: false, show_shortcuts: false, show_branded_background_image: false, show_cards: false, show_search_widget: false, show_clock: false, show_brave_news: false, show_together: false}' "$BRAVE_PREFS" > "$BRAVE_PREFS.tmp"
  mv "$BRAVE_PREFS.tmp" "$BRAVE_PREFS"
  log_message "Dashboard customizer applied"
}

set_brave_dark_mode() {
  log_message "Enabling dark mode..."
  touch "$HOME/.brave_debloat_dark_mode"
  log_message "Dark mode enabled—restart Brave!"
}

# Menu
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
  echo "=== Brave Browser Optimization Menu (macOS) ==="
  echo "1. Apply Default Optimizations (Recommended)"
  echo "2. Install Brave and Apply Optimizations"
  echo "3. Change Search Engine"
  echo "4. Toggle Hardware Acceleration"
  echo "5. Disable Analytics & Data Collection"
  echo "6. Toggle Memory Saver"
  echo "7. UI Improvements"
  echo "8. Dashboard Customization"
  echo "9. Remove Brave Rewards/VPN/Wallet"
  echo "10. Install Dashboard Customizer Extension"
  echo "11. Enable Dark Mode"
  echo "12. Revert All Changes"
  echo "13. Exit"
  echo "Pick options (e.g., '1 3'): "
}

main() {
  locate_brave
  create_wrapper
  while true; do
    show_menu
    read -p "> " choices
    IFS=' ' read -ra opts <<< "$choices"
    for opt in "${opts[@]}"; do
      case $opt in
        1) apply_default_optimizations ;;
        2) install_brave_and_optimize ;;
        3) set_search_engine ;;
        4) toggle_hardware_acceleration ;;
        5) toggle_analytics ;;
        6) toggle_memory_saver ;;
        7) toggle_ui_improvements ;;
        8) modify_dashboard_preferences ;;
        9) toggle_brave_features ;;
        10) install_dashboard_customizer ;;
        11) set_brave_dark_mode ;;
        12) revert_all_changes ;;
        13) log_message "Exiting—enjoy your debloated Brave!"; exit 0 ;;
        *) log_error "Invalid option: $opt"; sleep 2 ;;
      esac
    done
    log_message "Done—restart Brave for changes!"
    sleep 2
  done
}

revert_all_changes() {
  log_message "Reverting all changes..."
  rm -rf "$POLICY_DIR"/* "$EXT_DIR"/* "$THEMES_DIR"/* "$DASHBOARD_DIR" "$WRAPPER_PATH" "$APP_DIR" "$HOME/.brave_debloat_dark_mode"
  [ -f "$BRAVE_PREFS" ] && rm -f "$BRAVE_PREFS"
  [ -f "$LOCAL_STATE" ] && rm -f "$LOCAL_STATE"
  log_message "Changes reverted—restart Brave!"
}

# Kick it off
main