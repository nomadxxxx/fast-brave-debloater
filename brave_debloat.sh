#!/usr/bin/env bash

echo "Script starting..."

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

download_file() {
    local url="$1"
    local output="$2"
    if command -v curl &> /dev/null; then
        timeout 60s curl -s "$url" -o "$output"
    elif command -v wget &> /dev/null; then
        timeout 60s wget -q "$url" -O "$output"
    else
        log_error "Neither curl nor wget is installed. Please install one."
        return 1
    fi
    [ ! -s "$output" ] && { log_error "Failed to download $url"; return 1; }
    return 0
}

check_file_size() {
    local file="$1"
    local min_size=50000 # 50K min
    local size=$(stat -c%s "$file" 2>/dev/null || wc -c < "$file")
    [ "$size" -lt "$min_size" ] && { log_error "File $file too small ($size < $min_size)"; return 1; }
    log_message "File size OK: $size bytes"
    return 0
}

locate_brave_files() {
    log_message "Locating Brave browser..."
    if command -v flatpak &> /dev/null; then
        BRAVE_FLATPAK=$(flatpak list --app | grep com.brave.Browser)
        if [ -n "$BRAVE_FLATPAK" ]; then
            log_message "Flatpak Brave installation detected"
            BRAVE_EXEC="flatpak run com.brave.Browser"
            PREFERENCES_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default"
            POLICY_DIR="${HOME}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/policies/managed"
            IS_FLATPAK=true
        fi
    fi
    if [ -z "$BRAVE_EXEC" ]; then
        BRAVE_EXEC="$(command -v brave-browser || command -v brave || command -v brave-browser-stable)"
        if [ -z "$BRAVE_EXEC" ]; then
            log_message "Brave not found. Install? (y/n)"
            read -p "> " install_choice
            [[ "$install_choice" =~ ^[Yy]$ ]] && install_brave_variant "stable" || { log_error "Brave required"; exit 1; }
            BRAVE_EXEC="$(command -v brave-browser || command -v brave || command -v brave-browser-stable)"
            [ -z "$BRAVE_EXEC" ] && { log_error "Installation failed"; exit 1; }
        fi
        PREFERENCES_DIR="${HOME}/.config/BraveSoftware/Brave-Browser/Default"
        POLICY_DIR="/etc/brave/policies/managed"
        IS_FLATPAK=false
    fi
    mkdir -p "$POLICY_DIR" "/usr/share/brave" "$PREFERENCES_DIR"
    BRAVE_PREFS="$PREFERENCES_DIR/Preferences"
    log_message "Brave executable: $BRAVE_EXEC"
    log_message "Policy directory: $POLICY_DIR"
    log_message "Preferences directory: $PREFERENCES_DIR"
}

install_brave_variant() {
    local variant="$1"
    local script_url=""
    case "$variant" in
        "stable") script_url="${GITHUB_BASE}/brave_install/install_brave_stable.sh";;
        "beta") script_url="${GITHUB_BASE}/brave_install/install_brave_beta.sh";;
        "nightly") script_url="${GITHUB_BASE}/brave_install/install_brave_nightly.sh";;
        *) log_error "Invalid Brave variant: $variant"; return 1;;
    esac
    local temp_script=$(mktemp)
    download_file "$script_url" "$temp_script" || { log_error "Failed to download install script"; return 1; }
    chmod +x "$temp_script"
    "$temp_script"
    rm "$temp_script"
    if command -v brave-browser &> /dev/null || command -v brave &> /dev/null || command -v brave-browser-beta &> /dev/null || command -v brave-browser-nightly &> /dev/null; then
        log_message "Brave ($variant) installed successfully"
        return 0
    fi
    if [ "$variant" = "stable" ]; then
        log_message "Trying official install script..."
        curl -fsS https://dl.brave.com/install.sh | sh
        command -v brave-browser &> /dev/null || command -v brave &> /dev/null || { log_error "All install methods failed"; return 1; }
        log_message "Brave (stable) installed via official script"
        return 0
    fi
    log_error "Installation of Brave ($variant) failed"
    return 1
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
DARK_MODE_FLAG="/tmp/brave_debloat_dark_mode"
DARK_MODE=""
[ -f "$DARK_MODE_FLAG" ] && DARK_MODE="--force-dark-mode"
log_message "Launching Brave with managed extensions"
exec "$BRAVE_EXEC" $EXTENSION_ARGS --homepage=chrome://newtab $DARK_MODE "$@"
EOF
    chmod +x "$wrapper_path"
    log_message "Wrapper script created at $wrapper_path"
}

apply_policy() {
    local policy_name="$1"
    local policy_file="${POLICY_DIR}/${policy_name}.json"
    local local_policy="./policies/${policy_name}.json"
    log_message "Applying ${policy_name} policy..."
    if [ -f "$local_policy" ]; then
        log_message "Using local $local_policy"
        cp "$local_policy" "$policy_file" || { log_error "Copy failed"; return 1; }
    else
        log_message "Local not found, downloading from GitHub"
        download_file "${GITHUB_BASE}/policies/${policy_name}.json" "$policy_file" || { log_error "Download failed"; return 1; }
    fi
    chmod 644 "$policy_file"
    log_message "${policy_name} policy applied"
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

create_desktop_entry() {
    log_message "Creating desktop entry..."
    create_brave_wrapper
    local icon_path="/usr/share/icons/hicolor/256x256/apps/brave-debloat.png"
    local desktop_file="/usr/share/applications/brave-debloat.desktop"
    local local_icon="./assets/brave_icon.png"
    if [ -f "$local_icon" ]; then
        log_message "Copying $local_icon to $icon_path"
        mkdir -p "/usr/share/icons/hicolor/256x256/apps" || log_error "Dir creation failed"
        cp "$local_icon" "$icon_path" || log_error "Copy failed"
        chmod 644 "$icon_path" || log_error "Chmod failed"
        file "$icon_path" | grep -q "PNG" || log_error "Invalid PNG: $icon_path"
    else
        log_message "Warning: $local_icon not found, using default"
        icon_path="brave-browser"
    fi
    cat > "$desktop_file" << EOF
[Desktop Entry]
Version=1.0
Name=Brave Debloat
GenericName=Web Browser
Comment=Debloated and optimized Brave browser
Exec=/usr/local/bin/brave-debloat-wrapper %U
Icon=${icon_path##*/}
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
    [ -f "$icon_path" ] && command -v gtk-update-icon-cache &> /dev/null && gtk-update-icon-cache -f -t /usr/share/icons/hicolor
    log_message "Desktop entry created"
}

install_extension_from_crx() {
    local ext_id="$1" ext_name="$2" crx_url="$3"
    local ext_dir="/usr/share/brave/extensions/${ext_id}"
    local crx_path="/usr/share/brave/extensions/${ext_id}.crx"
    local local_crx="./extensions/${ext_id}.crx"
    local fallback_url="https://clients2.google.com/service/update2/crx?response=redirect&prodversion=91.0.4472.124&x=id%3D${ext_id}%26uc"
    [ -d "$ext_dir" ] && [ -f "$ext_dir/manifest.json" ] && { log_message "$ext_name already installed"; return 0; }
    log_message "Cleaning up $ext_name..."
    rm -rf "$ext_dir"
    log_message "Installing $ext_name..."
    mkdir -p "/usr/share/brave/extensions"
    if [ -f "$local_crx" ]; then
        log_message "Copying local $local_crx"
        cp "$local_crx" "$crx_path" || { log_error "Copy failed"; return 1; }
    else
        log_message "Local not found, downloading $crx_url"
        if ! timeout 60s curl -s -L "$crx_url" -o "$crx_path" || ! check_file_size "$crx_path"; then
            log_message "Primary failed, trying $fallback_url"
            rm -f "$crx_path"
            timeout 60s curl -s -L "$fallback_url" -o "$crx_path" && check_file_size "$crx_path" || { log_error "Download failed"; return 1; }
        fi
    fi
    chmod 644 "$crx_path"
    mkdir -p "$ext_dir"
    log_message "Unzipping $crx_path (size: $(du -h "$crx_path" | cut -f1))"
    if command -v pv >/dev/null; then
        unzip -o "$crx_path" -d "$ext_dir" | pv -l >/dev/null || { log_error "Unzip failed"; ls -l "$crx_path"; return 1; }
    else
        unzip -o "$crx_path" -d "$ext_dir" || { log_error "Unzip failed (install pv)"; ls -l "$crx_path"; return 1; }
    fi
    rm -rf "$ext_dir/_metadata"
    [ -f "$ext_dir/manifest.json" ] || { log_error "Manifest missing"; ls -l "$ext_dir"; return 1; }
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

install_theme() {
    local theme_id="$1" theme_name="$2" crx_url="$3"
    local theme_dir="/usr/share/brave/themes/${theme_id}"
    log_message "Installing theme: $theme_name..."
    [ "$theme_id" = "brave_dark_mode" ] && { set_brave_dark_mode; return 0; }
    [ -d "$theme_dir" ] && [ ! -f "$theme_dir/_metadata" ] && { log_message "Theme $theme_name already installed"; return 0; }
    log_message "Cleaning up $theme_name..."
    rm -rf "$theme_dir"
    [ -f "${POLICY_DIR}/dark_mode.json" ] && { log_message "Disabling dark mode for theme"; rm -f "${POLICY_DIR}/dark_mode.json" "/tmp/brave_debloat_dark_mode"; }
    mkdir -p "/usr/share/brave/themes"
    local crx_path="/usr/share/brave/themes/${theme_id}.crx"
    download_file "$crx_url" "$crx_path" || { log_error "Failed to download theme"; return 1; }
    chmod 644 "$crx_path"
    mkdir -p "$theme_dir"
    unzip -o "$crx_path" -d "$theme_dir" >/dev/null 2>&1
    rm -rf "$theme_dir/_metadata"
    update_extension_settings "$theme_id" "$theme_name"
    update_desktop_with_extensions
    log_message "Theme $theme_name activated"
    pkill -9 -f "brave.*" || true
    log_message "Brave restarted for theme"
}

select_theme() {
    log_message "Loading available themes..."
    local temp_file=$(mktemp)
    download_file "${GITHUB_BASE}/policies/consolidated_extensions.json" "$temp_file" || { log_error "Failed to download theme data"; rm "$temp_file"; return 1; }
    local theme_count=$(jq '.categories.themes | length' "$temp_file")
    [ "$theme_count" -eq 0 ] && { log_error "No themes found"; rm "$temp_file"; return 1; }
    echo -e "\n=== Available Themes ==="
    local i=1
    declare -A theme_map
    while read -r id && read -r name && read -r description && read -r crx_url; do
        printf "%2d. %-35s - %s\n" "$i" "$name" "$description"
        theme_map["$i"]="$id|$name|$crx_url"
        ((i++))
    done < <(jq -r '.categories.themes[] | (.id, .name, .description, .crx_url)' "$temp_file")
    echo -e "\nSelect a theme to install (1-$((i-1))): "
    read theme_choice
    [ -n "${theme_map[$theme_choice]}" ] && { IFS='|' read -r id name crx_url <<< "${theme_map[$theme_choice]}"; install_theme "$id" "$name" "$crx_url"; } || log_error "Invalid selection: $theme_choice"
    rm "$temp_file"
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

install_brave_and_optimize() {
    log_message "Installing Brave and applying optimizations..."
    install_brave_variant "stable"
    apply_default_optimizations
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

apply_default_optimizations() {
    [ -z "$SILENT" ] && log_message "Applying default optimizations..."
    apply_policy "brave_optimizations"
    apply_policy "adblock"
    apply_policy "privacy"
    apply_policy "ui"
    apply_policy "features"
    create_desktop_entry
    [ -z "$SILENT" ] && log_message "Installing recommended extensions..."
    install_extension_from_crx "cjpalhdlnbpafiamejdnhcphjbkeiagm" "uBlock Origin" "https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/cjpalhdlnbpafiamejdnhcphjbkeiagm.crx"
    install_extension_from_crx "eimadpbcbfnmbkopoojfekhnkhdbieeh" "Dark Reader" "https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/eimadpbcbfnmbkopoojfekhnkhdbieeh.crx"
    install_theme "annfbnbieaamhaimclajlajpijgkdblo" "Dark Theme for Google Chrome" "https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/themes/annfbnbieaamhaimclajlajpijgkdblo.crx"
    LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
    [ -f "$LOCAL_STATE" ] && { jq -e '.browser.enabled_labs_experiments' "$LOCAL_STATE" >/dev/null 2>&1 && jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "$LOCAL_STATE" > "$LOCAL_STATE.tmp" || jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "$LOCAL_STATE" > "$LOCAL_STATE.tmp"; mv "$LOCAL_STATE.tmp" "$LOCAL_STATE"; [ -z "$SILENT" ] && log_message "Enabled ad blocking flag"; }
    install_dashboard_customizer
    [ -z "$SILENT" ] && log_message "Optimizations and dashboard applied" && log_message "Restart Brave for changes"
}

update_desktop_with_extensions() {
    local desktop_file="/usr/share/applications/brave-debloat.desktop"
    log_message "Updating desktop entry with extensions..."
    [ ! -f "$desktop_file" ] && create_desktop_entry
    local brave_exec=$(grep "^Exec=" "$desktop_file" | head -1 | sed -E 's/Exec=([^ ]+).*/\1/')
    local extensions_dir="/usr/share/brave/extensions"
    local dashboard_dir="/usr/share/brave/extensions/dashboard-customizer"
    local extension_paths=""
    [ -d "$dashboard_dir" ] && extension_paths="$dashboard_dir"
    [ -d "$extensions_dir" ] && for ext_dir in "$extensions_dir"/*; do [ -d "$ext_dir" ] && [ "$ext_dir" != "$dashboard_dir" ] && extension_paths="${extension_paths:+$extension_paths,}$ext_dir"; done
    [ -n "$extension_paths" ] && { local temp_file=$(mktemp); while IFS= read -r line; do [[ "$line" =~ ^Exec= ]] && { [[ "$line" =~ --load-extension= ]] && line=$(echo "$line" | sed -E "s|(--load-extension=)[^ ]*|\1$extension_paths|") || line="Exec=${brave_exec} --load-extension=${extension_paths} $(echo "$line" | sed -E "s|^Exec=${brave_exec} ?||")"; [[ "$line" =~ --homepage= ]] || line="$line --homepage=chrome://newtab"; }; echo "$line" >> "$temp_file"; done < "$desktop_file"; mv "$temp_file" "$desktop_file"; chmod 644 "$desktop_file"; log_message "Desktop updated with extensions"; } || log_message "No extra extensions"
}

set_brave_dark_mode() {
    local policy_file="${POLICY_DIR}/dark_mode.json"
    [ -f "$policy_file" ] && { log_message "Dark mode already enabled"; return; }
    cat > "$policy_file" << EOF
{
  "ForceDarkModeEnabled": true
}
EOF
    chmod 644 "$policy_file"
    touch "/tmp/brave_debloat_dark_mode"
    log_message "Dark mode enabled"
    update_desktop_with_extensions
    pkill -9 -f "brave.*" || true
    log_message "Brave restarted for dark mode"
}

toggle_hardware_acceleration() {
    local policy_file="${POLICY_DIR}/hardware.json"
    if [ -f "$policy_file" ]; then
        log_message "Hardware acceleration ENABLED"
        read -p "Disable? (y/n): " disable_choice
        [[ "$disable_choice" =~ ^[Yy]$ ]] && cat > "$policy_file" << EOF
{
  "HardwareAccelerationModeEnabled": false
}
EOF
        log_message "Hardware acceleration disabled"
    else
        cat > "$policy_file" << EOF
{
  "HardwareAccelerationModeEnabled": true
}
EOF
        chmod 644 "$policy_file"
        log_message "Hardware acceleration enabled"
    fi
}

toggle_analytics() {
    local policy_file="${POLICY_DIR}/privacy.json"
    if [ -f "$policy_file" ]; then
        log_message "Analytics DISABLED"
        read -p "Enable? (y/n): " enable_choice
        [[ "$enable_choice" =~ ^[Yy]$ ]] && { rm -f "$policy_file"; log_message "Enabled"; } || log_message "Remains disabled"
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
        log_message "Analytics disabled"
    fi
}

toggle_custom_scriptlets() {
    local policy_file="${POLICY_DIR}/scriptlets.json"
    if [ -f "$policy_file" ]; then
        log_message "Custom scriptlets ENABLED"
        read -p "Disable? (y/n): " disable_choice
        [[ "$disable_choice" =~ ^[Yy]$ ]] && { rm -f "$policy_file"; log_message "Disabled"; } || log_message "Remains enabled"
    else
        log_message "WARNING: Experimental feature"
        read -p "Enable? (y/n): " enable_choice
        [[ "$enable_choice" =~ ^[Yy]$ ]] && { cat > "$policy_file" << EOF
{
  "EnableCustomScriptlets": true
}
EOF
        chmod 644 "$policy_file"; log_message "Enabled"; }
    fi
}

toggle_background_running() {
    local policy_file="${POLICY_DIR}/background.json"
    if [ -f "$policy_file" ]; then
        log_message "Background running DISABLED"
        read -p "Enable? (y/n): " enable_choice
        [[ "$enable_choice" =~ ^[Yy]$ ]] && { rm -f "$policy_file"; log_message "Enabled"; } || log_message "Remains disabled"
    else
        log_message "WARNING: May cause instability"
        read -p "Disable? (y/n): " disable_choice
        [[ "$disable_choice" =~ ^[Yy]$ ]] && { cat > "$policy_file" << EOF
{
  "BackgroundModeEnabled": false
}
EOF
        chmod 644 "$policy_file"; log_message "Disabled"; }
    fi
}

toggle_memory_saver() {
    local policy_file="${POLICY_DIR}/memory_saver.json"
    if [ -f "$policy_file" ]; then
        log_message "Memory saver ENABLED"
        read -p "Disable? (y/n): " disable_choice
        [[ "$disable_choice" =~ ^[Yy]$ ]] && { rm -f "$policy_file"; log_message "Disabled"; } || log_message "Remains enabled"
    else
        cat > "$policy_file" << EOF
{
  "MemorySaverModeEnabled": true
}
EOF
        chmod 644 "$policy_file"
        log_message "Memory saver enabled"
    fi
}

toggle_ui_improvements() { toggle_policy "ui" "UI Improvements"; }
toggle_brave_features() { toggle_policy "features" "Brave Rewards/VPN/Wallet"; }

toggle_experimental_adblock() {
    LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
    if [ -f "$LOCAL_STATE" ] && jq -e '.browser.enabled_labs_experiments | index("brave-adblock-experimental-list-default@1")' "$LOCAL_STATE" >/dev/null 2>&1; then
        log_message "Experimental ad blocking ENABLED"
        read -p "Disable? (y/n): " disable_choice
        [[ "$disable_choice" =~ ^[Yy]$ ]] && { jq 'del(.browser.enabled_labs_experiments[] | select(. == "brave-adblock-experimental-list-default@1"))' "$LOCAL_STATE" > "$LOCAL_STATE.tmp"; mv "$LOCAL_STATE.tmp" "$LOCAL_STATE"; log_message "Disabled"; } || log_message "Remains enabled"
    else
        log_message "Enabling experimental ad blocking..."
        [ -f "$LOCAL_STATE" ] && { jq -e '.browser.enabled_labs_experiments' "$LOCAL_STATE" >/dev/null 2>&1 && jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default@1"]' "$LOCAL_STATE" > "$LOCAL_STATE.tmp" || jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default@1"]' "$LOCAL_STATE" > "$LOCAL_STATE.tmp"; } || echo '{"browser": {"enabled_labs_experiments": ["brave-adblock-experimental-list-default@1"]}}' > "$LOCAL_STATE.tmp"
        mv "$LOCAL_STATE.tmp" "$LOCAL_STATE"
        chmod 644 "$LOCAL_STATE"
        log_message "Enabled"
    fi
}

install_recommended_extensions() {
    log_message "Loading recommended extensions..."
    local temp_file=$(mktemp)
    download_file "${GITHUB_BASE}/policies/consolidated_extensions.json" "$temp_file" || { log_error "Failed to download extension data"; rm "$temp_file"; return 1; }
    local ext_count=$(jq '[.categories | to_entries[] | select(.key != "themes") | .value[]] | length' "$temp_file")
    [ "$ext_count" -eq 0 ] && { log_error "No extensions found"; cat "$temp_file"; rm "$temp_file"; return 1; }
    clear
    echo "=== Recommended Extensions ==="
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
    read -p "> " choices
    [ "$choices" = "0" ] && { log_message "Exiting installer"; rm "$temp_file"; return 0; }
    [ "$choices" = "all" ] && { for key in "${!ext_map[@]}"; do IFS='|' read -r id name crx_url <<< "${ext_map[$key]}"; install_extension_from_crx "$id" "$name" "$crx_url"; done; } || { IFS=' ' read -ra selected_options <<< "$choices"; for choice in "${selected_options[@]}"; do [ -n "${ext_map[$choice]}" ] && { IFS='|' read -r id name crx_url <<< "${ext_map[$choice]}"; install_extension_from_crx "$id" "$name" "$crx_url"; } || log_error "Invalid selection: $choice"; done; }
    rm "$temp_file"
    log_message "Extensions installed—running optimizations..."
    SILENT=1 apply_default_optimizations
    log_message "Extensions processed"
}

install_dashboard_customizer() {
    local ext_id="dashboard-customizer"
    local ext_name="Dashboard Customizer"
    local crx_url="https://raw.githubusercontent.com/nomadxxxx/fast-brave-debloater/main/extensions/dashboard-customizer.crx"
    local ext_dir="/usr/share/brave/extensions/${ext_id}"
    local crx_path="/usr/share/brave/${ext_id}.crx"
    local local_crx="./brave-dashboard-customizer/brave-dashboard-customizer.crx"
    log_message "Installing $ext_name..."
    [ -d "$ext_dir" ] && [ -f "$ext_dir/manifest.json" ] && { log_message "$ext_name already installed"; return; }
    log_message "Cleaning up $ext_name..."
    rm -rf "$ext_dir"
    if [ -f "$local_crx" ]; then
        log_message "Copying local $local_crx"
        cp "$local_crx" "$crx_path" || { log_error "Failed to copy"; return 1; }
    else
        log_message "Local not found, downloading $crx_url"
        download_file "$crx_url" "$crx_path" && check_file_size "$crx_path" || { log_error "Failed to download"; return 1; }
    fi
    chmod 644 "$crx_path"
    mkdir -p "$ext_dir"
    log_message "Unzipping $crx_path..."
    if command -v pv >/dev/null; then
        unzip -o "$crx_path" -d "$ext_dir" | pv -l >/dev/null || { log_error "Unzip failed"; ls -l "$crx_path"; return 1; }
    else
        unzip -o "$crx_path" -d "$ext_dir" || { log_error "Unzip failed (install pv)"; ls -l "$crx_path"; return 1; }
    fi
    rm -rf "$ext_dir/_metadata"
    [ -f "$ext_dir/manifest.json" ] || { log_error "Manifest missing"; ls -l "$ext_dir"; return 1; }
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
    log_message "Brave processes killed for $ext_name"
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
    echo "A script to debloat Brave browser and apply optimizations..."
    echo "*Note I am working on a new version of this script to cover smoothbrain Win and Mac users."
    echo
    echo "=== Brave Browser Optimization Menu ==="
    echo "1. Apply Default Optimizations (Recommended)"
    echo "   Enables core performance features, removes bloat, and installs uBlock Origin, Dark Reader, and Dashboard Customizer"
    echo "2. Install Brave and apply optimizations"
    echo "   Install Brave browser and apply recommended optimizations"
    echo "3. Change Search Engine"
    echo "   Choose from DuckDuckGo, SearXNG, Whoogle or traditional options"
    echo "4. Toggle Hardware Acceleration"
    echo "   Improves rendering performance using your GPU"
    echo "5. Disable Analytics & Data Collection"
    echo "   Stops background analytics and telemetry"
    echo "6. Enable Custom Scriptlets (Advanced)"
    echo "   WARNING: Only for advanced users. Allows custom JavaScript injection"
    echo "7. Disable Background Running"
    echo "   WARNING: May cause instability"
    echo "8. Toggle Memory Saver"
    echo "   Reduces memory usage by suspending inactive tabs"
    echo "9. UI Improvements"
    echo "   Shows full URLs, enables wide address bar, and bookmarks bar"
    echo "10. Dashboard Customization"
    echo "    Removes widgets and customizes the new tab page"
    echo "11. Remove Brave Rewards/VPN/Wallet"
    echo "    Disables cryptocurrency and rewards features"
    echo "12. Toggle Experimental Ad Blocking (experimental)"
    echo "    Enhanced ad blocking - Will check current status"
    echo "13. Install Recommended Brave extensions"
    echo "    Installs a curated set of recommended extensions"
    echo "14. Install Dashboard Customizer Extension"
    echo "    Replaces Brave's dashboard with a clean, black background and clock"
    echo "15. Enable Dark Mode"
    echo "    Forces Brave to use dark theme regardless of system settings"
    echo "16. Install Browser Theme"
    echo "    Choose from a selection of browser themes"
    echo "17. Revert All Changes"
    echo "    Removes all changes made by this script"
    echo "18. Exit"
    echo
    echo "You can select multiple options by entering numbers separated by spaces (e.g., 4 5 8)"
    echo "Note: Options 1, 2, and 17 cannot be combined with other options"
    echo
}

main() {
    locate_brave_files
    while true; do
        show_menu
        read -p "Enter your choice(s) [1-18]: " choices
        IFS=' ' read -ra selected_options <<< "$choices"
        local has_exclusive=0
        for choice in "${selected_options[@]}"; do
            [[ "$choice" =~ ^(1|2|17)$ ]] && has_exclusive=1
        done
        [ "$has_exclusive" -eq 1 ] && [ "${#selected_options[@]}" -gt 1 ] && { log_error "Options 1, 2, and 17 cannot be combined"; sleep 2.5; continue; }
        for choice in "${selected_options[@]}"; do
            case $choice in
                1) apply_default_optimizations; sleep 2.5;;
                2) install_brave_and_optimize; sleep 2.5;;
                3) set_search_engine; sleep 2.5;;
                4) toggle_hardware_acceleration; sleep 2.5;;
                5) toggle_analytics; sleep 2.5;;
                6) toggle_custom_scriptlets; sleep 2.5;;
                7) toggle_background_running; sleep 2.5;;
                8) toggle_memory_saver; sleep 2.5;;
                9) toggle_ui_improvements; sleep 2.5;;
                10) modify_dashboard_preferences; sleep 2.5;;
                11) toggle_brave_features; sleep 2.5;;
                12) toggle_experimental_adblock; sleep 4;;
                13) install_recommended_extensions; sleep 2.5;;
                14) install_dashboard_customizer; sleep 2.5;;
                15) set_brave_dark_mode; sleep 2.5;;
                16) select_theme; sleep 2.5;;
                17) read -p "Revert all changes? (y/n): " confirm; [[ "$confirm" =~ ^[Yy]$ ]] && revert_all_changes; sleep 2.5;;
                18) log_message "Exiting...\nThank you for using Brave debloat, lets make Brave great again."; sleep 2.5; exit 0;;
                *) log_error "Invalid option: $choice"; sleep 2.5;;
            esac
        done
        [ "${#selected_options[@]}" -gt 0 ] && log_message "All selected options processed.\nPlease restart Brave for changes to take effect." && sleep 2.5
    done
}

revert_all_changes() {
    log_message "Reverting all changes..."
    rm -rf "${POLICY_DIR}"/* "/usr/share/brave/extensions"/* "/usr/share/brave/themes"/* "/usr/share/brave/extensions/dashboard-customizer"/* "/usr/local/bin/brave-debloat-wrapper" "/usr/share/applications/brave-debloat.desktop" "/tmp/brave_debloat_dark_mode"
    [ -f "$BRAVE_PREFS" ] && rm -f "$BRAVE_PREFS"
    [ -f "${PREFERENCES_DIR%/*}/Local State" ] && rm -f "${PREFERENCES_DIR%/*}/Local State"
    log_message "All changes reverted"
}

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it first." >&2
    echo "Debian/Ubuntu: sudo apt install jq" >&2
    echo "Fedora:        sudo dnf install jq" >&2
    echo "Arch:          sudo pacman -S jq" >&2
    exit 1
fi

main