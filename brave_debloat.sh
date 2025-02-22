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
    
    BRAVE_EXEC="$(command -v brave || command -v brave-browser || command -v brave-browser-stable)"
    if [[ -z "${BRAVE_EXEC}" ]]; then
        log_error "Brave browser executable not found. Please install Brave first."
        exit 1
    fi
    
    BRAVE_REAL_PATH="$(readlink -f "${BRAVE_EXEC}")"
    POLICY_DIR="/etc/brave/policies/managed"
    PREFERENCES_DIR="${HOME}/.config/BraveSoftware/Brave-Browser/Default"
    
    mkdir -p "${POLICY_DIR}"
    mkdir -p "/usr/share/brave"
    
    # Copy icon if it exists in current directory
    if [[ -f "brave_icon.png" ]]; then
        cp brave_icon.png /usr/share/brave/
        chmod 644 /usr/share/brave/brave_icon.png
    fi
    
    log_message "Brave executable found at: ${BRAVE_REAL_PATH}"
    log_message "Policy directory: ${POLICY_DIR}"
}
# Function to create desktop entry
create_desktop_entry() {
    log_message "Creating desktop entry for Brave Debloat..."
    
    # Performance flags
    PERFORMANCE_FLAGS="--enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blocklist --enable-vulkan --enable-parallel-downloading"

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
    "DefaultSearchProviderName": "DuckDuckGo",
    "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}",
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
    local preferences_file="${PREFERENCES_DIR}/Preferences"
    
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
        echo "1. DuckDuckGo (Recommended)"
        echo "2. SearXNG (Recommended)"
        echo "3. Whoogle (Recommended)"
        echo "4. Yandex (enjoy russian botnet)"
        echo "5. Kagi (good, but enjoy paying)"
        echo "6. Google (welcome to the botnet)"
        echo "7. Bing (enjoy your AIDs)"
        echo "8. Back to main menu"
        
        read -p "Enter your choice [1-8]: " search_choice
        
        local policy_file="${POLICY_DIR}/search_provider.json"
        
        case ${search_choice} in
            1)
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
            2)
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
            3)
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
            4)
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
            5)
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
            6)
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
            7)
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
            8)
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
    
    log_message "Default optimizations applied successfully"
    log_message "Please restart Brave browser for changes to take effect"
}
# Show menu function with explanations
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
    echo "   Automatically frees memory from inactive tabs"
    echo
    echo "8. UI Improvements"
    echo "   Show full URLs, wide address bar, always show bookmarks"
    echo
    echo "9. Dashboard Customization"
    echo "   Disable Brave Stats, Search Widget, Enable Clock"
    echo
    echo "10. Remove Brave Rewards/VPN/Wallet"
    echo "    Removes cryptocurrency, VPN, and wallet promotional elements"
    echo
    echo "11. Exit"
}

# Main function
main() {
    locate_brave_files
    
    while true; do
        show_menu
        read -p "Enter your choice [1-11]: " choice
        
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
                modify_dashboard_preferences
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
                log_message "Exiting..."
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
