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

# Logging functions
log_message() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
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
                log_message "Installing Brave using official install script..."
                curl -fsS https://dl.brave.com/install.sh | sh
                
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
    
    # Copy icon if it exists in current directory
    if [[ -f "brave_icon.png" ]]; then
        cp brave_icon.png /usr/share/brave/
        chmod 644 /usr/share/brave/brave_icon.png
    fi
    
    # Set the preferences file path
    BRAVE_PREFS="${PREFERENCES_DIR}/Preferences"
    
    log_message "Brave executable: ${BRAVE_EXEC}"
    log_message "Policy directory: ${POLICY_DIR}"
    log_message "Preferences directory: ${PREFERENCES_DIR}"
}
# Function to create desktop entry
create_desktop_entry() {
    log_message "Creating desktop entry for Brave Debloat..."
    
    # Performance flags
    PERFORMANCE_FLAGS="--enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --enable-vulkan --enable-parallel-downloading --enable-features=brave-adblock-experimental-list-default"

    # Create desktop entry
    cat > "/usr/share/applications/brave-debloat.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=Brave Debloat
Comment=Privacy-focused web browser with optimizations
Exec=brave ${PERFORMANCE_FLAGS} %U
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
Icon=/usr/share/brave/brave_icon.png
EOF

    chmod 644 "/usr/share/applications/brave-debloat.desktop"
    
    log_message "Desktop entry created"
}

# Function to apply policies
apply_brave_policies() {
    local policy_file="${POLICY_DIR}/brave_optimizations.json"
    
    cat > "${policy_file}" << EOF
{
    "HardwareAccelerationModeEnabled": true,
    "MemorySaverEnabled": true,
    "BraveRewardsDisabled": true,
    "BraveVPNDisabled": true,
    "BraveWalletDisabled": true,
    "BraveAIChatEnabled": false,
    "AutomaticallySendAnalytics": false,
    "SafeBrowsingEnabled": false,
    "BackgroundModeEnabled": false,
    "DefaultSearchProviderEnabled": true,
    "DefaultSearchProviderName": "Brave Search",
    "DefaultSearchProviderSearchURL": "https://search.brave.com/search?q={searchTerms}",
    "ShowFullURLs": true,
    "WideAddressBar": true,
    "BookmarksBarEnabled": true,
    "SyncDisabled": true,
    "BraveSyncEnabled": false
}
EOF

    chmod 644 "${policy_file}"
    log_message "Applied system-wide Brave policies"
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
        .brave.new_tab_page.show_search_widget = false' "${preferences_file}" > "${temp_file}"
    
    mv "${temp_file}" "${preferences_file}"
    chmod 644 "${preferences_file}"
    
    log_message "Modified dashboard preferences"
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

# Function to apply default optimizations
apply_default_optimizations() {
    log_message "Applying default optimizations..."
    
    apply_brave_policies
    create_desktop_entry
    modify_dashboard_preferences
    
    # Enable experimental ad blocking in the default optimizations
    log_message "Enabling Experimental Ad Blocking..."
    # Create policy file
    cat > "${POLICY_DIR}/adblock.json" << EOF
{
    "ShieldsAdvancedView": true,
    "BraveExperimentalAdblockEnabled": true
}
EOF
    chmod 644 "${POLICY_DIR}/adblock.json"
    
    # Also modify preferences
    if [[ -f "${BRAVE_PREFS}" ]]; then
        jq '.brave = (.brave // {}) | 
            .brave.shields = (.brave.shields // {}) |
            .brave.shields.advanced_view_enabled = true |
            .brave.shields.experimental_filters_enabled = true' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
        mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
    fi
    
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
        log_message "Enabled experimental adblock flag in browser flags"
    fi
    
    log_message "Default optimizations applied successfully"
    log_message "Please restart Brave browser for changes to take effect"
}
# Show menu function
show_menu() {
    clear
    echo "
██████╗ ██████╗  █████╗ ██╗   ██╗███████╗    ██████╗ ███████╗██████╗ ██╗      ██████╗  █████╗ ████████╗
██╔══██╗██╔══██╗██╔══██╗██║   ██║██╔════╝    ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗██╔══██╗╚══██╔══╝
██████╔╝██████╔╝███████║██║   ██║█████╗      ██║  ██║█████╗  ██████╔╝██║     ██║   ██║███████║   ██║   
██╔══██╗██╔══██╗██╔══██║╚██╗ ██╔╝██╔══╝      ██║  ██║██╔══╝  ██╔══██╗██║     ██║   ██║██╔══██║   ██║   
██████╔╝██║  ██║██║  ██║ ╚████╔╝ ███████╗    ██████╔╝███████╗██████╔╝███████╗╚██████╔╝██║  ██║   ██║   
╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝    ╚═════╝ ╚══════╝╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   
"
    echo "A script to debloat Brave brower and apply optimizations..."
    echo "*Note I am working on a new version of this script to cover smoothbrain Win and Mac users."
    echo
    echo "=== Brave Browser Optimization Menu ==="
    echo "1. Apply Default Optimizations (Recommended)"
    echo "   Enables core performance features and removes unnecessary bloat"
    echo
    echo "2. Change Search Engine"
    echo "   Choose from DuckDuckGo, SearXNG, Whoogle or traditional options"
    echo
    echo "3. Toggle Hardware Acceleration"
    echo "   Improves rendering performance using your GPU"
    echo
    echo "4. Disable Analytics & Data Collection"
    echo "   Stops background analytics and telemetry"
    echo
    echo "5. Enable Custom Scriptlets (Advanced)"
    echo "   WARNING: Only for advanced users. Allows custom JavaScript injection"
    echo
    echo "6. Disable Background Running"
    echo "   WARNING: May cause instability"
    echo
    echo "7. Toggle Memory Saver"
    echo "   Reduces memory usage by suspending inactive tabs"
    echo
    echo "8. UI Improvements"
    echo "   Shows full URLs, enables wide address bar, and bookmarks bar"
    echo
    echo "9. Dashboard Customization"
    echo "   Removes widgets and customizes the new tab page"
    echo
    echo "10. Remove Brave Rewards/VPN/Wallet"
    echo "    Disables cryptocurrency and rewards features"
    echo
    echo "11. Toggle Experimental Ad Blocking (ON/OFF)"
    echo "    Enhanced ad blocking - Current status will be shown"
    echo
    echo "12. Exit"
    echo
}

# Main function
main() {
    locate_brave_files
    
    while true; do
        show_menu
        read -p "Enter your choice [1-12]: " choice
        
        case ${choice} in
            1) 
                apply_default_optimizations
                sleep 2.5
                ;;
            2) 
                set_search_engine
                sleep 2.5
                ;;
            3) 
                log_message "Toggling hardware acceleration..."
                cat > "${POLICY_DIR}/hardware.json" << EOF
{
    "HardwareAccelerationModeEnabled": true
}
EOF
                chmod 644 "${POLICY_DIR}/hardware.json"
                sleep 2.5
                ;;
            4) 
                log_message "Disabling analytics and data collection..."
                cat > "${POLICY_DIR}/privacy.json" << EOF
{
    "MetricsReportingEnabled": false,
    "CloudReportingEnabled": false,
    "SafeBrowsingExtendedReportingEnabled": false,
    "AutomaticallySendAnalytics": false
}
EOF
                chmod 644 "${POLICY_DIR}/privacy.json"
                sleep 2.5
                ;;
            5)
                log_message "WARNING: Custom scriptlets are an advanced feature"
                cat > "${POLICY_DIR}/scriptlets.json" << EOF
{
    "ShieldsAdvancedView": true,
    "EnableCustomScriptlets": true
}
EOF
                chmod 644 "${POLICY_DIR}/scriptlets.json"
                sleep 2.5
                ;;
            6)
                log_message "WARNING: Disabling background running may cause instability"
                cat > "${POLICY_DIR}/background.json" << EOF
{
    "BackgroundModeEnabled": false
}
EOF
                chmod 644 "${POLICY_DIR}/background.json"
                sleep 2.5
                ;;
            7)
                log_message "Toggling Memory Saver..."
                cat > "${POLICY_DIR}/memory.json" << EOF
{
    "MemorySaverEnabled": true
}
EOF
                chmod 644 "${POLICY_DIR}/memory.json"
                sleep 2.5
                ;;
            8)
                log_message "Applying UI improvements..."
                cat > "${POLICY_DIR}/ui.json" << EOF
{
    "ShowFullURLs": true,
    "WideAddressBar": true,
    "BookmarksBarEnabled": true
}
EOF
                chmod 644 "${POLICY_DIR}/ui.json"
                sleep 2.5
                ;;
            9)
                log_message "Customizing dashboard..."
                if [[ -f "${BRAVE_PREFS}" ]]; then
                    jq '.brave = (.brave // {}) | 
                        .brave.stats = (.brave.stats // {}) |
                        .brave.stats.enabled = false |
                        .brave.today = (.brave.today // {}) |
                        .brave.today.should_show_brave_today_widget = false |
                        .brave.new_tab_page = (.brave.new_tab_page // {}) |
                        .brave.new_tab_page.show_clock = true |
                        .brave.new_tab_page.show_search_widget = false' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
                    mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
                    log_message "Dashboard preferences modified successfully"
                else
                    log_error "Preferences file not found"
                fi
                sleep 2.5
                ;;
            10)
                log_message "Removing Brave Rewards/VPN/Wallet..."
                cat > "${POLICY_DIR}/features.json" << EOF
{
    "BraveRewardsDisabled": true,
    "BraveVPNDisabled": true,
    "BraveWalletDisabled": true,
    "BraveAIChatEnabled": false
}
EOF
                chmod 644 "${POLICY_DIR}/features.json"
                sleep 2.5
                ;;
            11)
    log_message "Checking current experimental ad blocking status..."
    if [[ -f "${BRAVE_PREFS}" ]]; then
        if jq -e '.brave.shields.experimental_filters_enabled // false' "${BRAVE_PREFS}" >/dev/null 2>&1; then
            log_message "Experimental Ad Blocking is currently ENABLED"
            read -p "Would you like to disable it? (y/n): " disable_choice
            if [[ "${disable_choice}" =~ ^[Yy]$ ]]; then
                # Remove policy file
                rm -f "${POLICY_DIR}/adblock.json"
                
                # Update preferences
                jq '.brave = (.brave // {}) | 
                    .brave.shields = (.brave.shields // {}) |
                    .brave.shields.experimental_filters_enabled = false' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
                mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
                
                # Disable the flag in Local State
                LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
                if [[ -f "${LOCAL_STATE}" ]]; then
                    jq 'del(.browser.enabled_labs_experiments[] | select(. == "brave-adblock-experimental-list-default"))' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
                    mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
                fi
                
                # Remove flag from desktop entry
                if grep -q -- "--enable-features=brave-adblock-experimental-list-default" "/usr/share/applications/brave-debloat.desktop"; then
                    sed -i 's/--enable-features=brave-adblock-experimental-list-default//' "/usr/share/applications/brave-debloat.desktop"
                    log_message "Removed experimental adblock flag from desktop entry"
                fi
                
                log_message "Experimental Ad Blocking has been DISABLED"
            fi
        else
            log_message "Experimental Ad Blocking is currently DISABLED"
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
                
                # Update preferences
                jq '.brave = (.brave // {}) | 
                    .brave.shields = (.brave.shields // {}) |
                    .brave.shields.experimental_filters_enabled = true |
                    .brave.shields.advanced_view_enabled = true' "${BRAVE_PREFS}" > "${BRAVE_PREFS}.tmp"
                mv "${BRAVE_PREFS}.tmp" "${BRAVE_PREFS}"
                
                # Enable the flag in Local State
                LOCAL_STATE="${PREFERENCES_DIR%/*}/Local State"
                if [[ -f "${LOCAL_STATE}" ]]; then
                    # Check if the file contains the browser.enabled_labs_experiments key
                    if jq -e '.browser.enabled_labs_experiments' "${LOCAL_STATE}" >/dev/null 2>&1; then
                        # Add the flag if it doesn't exist
                        jq '.browser.enabled_labs_experiments += ["brave-adblock-experimental-list-default"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
                    else
                        # Create the key if it doesn't exist
                        jq '.browser = (.browser // {}) | .browser.enabled_labs_experiments = ["brave-adblock-experimental-list-default"]' "${LOCAL_STATE}" > "${LOCAL_STATE}.tmp"
                    fi
                    mv "${LOCAL_STATE}.tmp" "${LOCAL_STATE}"
                    log_message "Enabled experimental adblock flag in browser flags"
                fi
                
                # Add flag to desktop entry
                if grep -q "Exec=brave" "/usr/share/applications/brave-debloat.desktop"; then
                    if ! grep -q -- "--enable-features=brave-adblock-experimental-list-default" "/usr/share/applications/brave-debloat.desktop"; then
                        sed -i 's/Exec=brave/Exec=brave --enable-features=brave-adblock-experimental-list-default/' "/usr/share/applications/brave-debloat.desktop"
                        log_message "Added experimental adblock flag to desktop entry"
                    fi
                fi
                
                log_message "Experimental Ad Blocking has been ENABLED"
            fi
        fi
        log_message "Please COMPLETELY QUIT Brave browser and restart for changes to take effect"
        log_message "After restart, check brave://components/ and update 'Brave Ad Block Updater' if needed"
    else
        log_error "Preferences file not found"
    fi
    sleep 4
    ;;
            12)
                log_message "Exiting...
Thank you for using Brave debloat, lets make Brave great again."
                sleep 5.0
                exit 0
                ;;
            *)
                log_error "Invalid option"
                sleep 2.5
                ;;
        esac
    done
}

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Please install it first."
    exit 1
fi

# Run main script
main
PERFORMANCE_FLAGS="--enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --enable-vulkan --enable-parallel-downloading --enable-features=BraveAdblockExperimental"