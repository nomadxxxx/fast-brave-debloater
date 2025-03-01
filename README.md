
<p align="center">
  <img src="https://github.com/nomadxxxx/fast-brave-debloater/blob/main/assets/FastBraveDebloat_logo_small.png?raw=true" />
</p>
<p align="center">
A powerful optimization script that transforms Brave Browser into a privacy-focused browsing experience. This script removes unnecessary bloat, enhances performance, and automates installation.
</p>
<p align="center">
  <img src="https://img.shields.io/badge/-Linux-ff7a18?style=flat-square&logo=linux&logoColor=white" alt="Linux Badge">
  <img src="https://img.shields.io/badge/-macOS-ff7a18?style=flat-square&logo=apple&logoColor=white" alt="macOS Badge">
  <img src="https://img.shields.io/github/stars/nomadxxxx/fast-brave-debloater?style=flat-square&color=ff7a18" alt="GitHub Repo stars">
  <img src="https://img.shields.io/github/forks/nomadxxxx/fast-brave-debloater?style=flat-square&color=ff7a18" alt="GitHub Forks">
  <img src="https://img.shields.io/badge/-Bash-ff7a18?style=flat-square&logo=gnu-bash&logoColor=white" alt="Bash Badge">
  <img src="https://img.shields.io/badge/-jq-ff7a18?style=flat-square&logo=jq&logoColor=white" alt="jq Badge">
</p>

## Key Features
### Removes Brave Bloat
❌ Eliminates cryptocurrency wallet and related UI elements  
❌ Removes Brave VPN promotions and notifications  
❌ Disables Brave Rewards system completely  
❌ Removes LeoAI Chat suggestions and integrations  
❌ Eliminates unnecessary background processes (Brave Sync, etc.)  

### Enhances Performance
✅ Enables GPU acceleration for smoother browsing  
✅ Implements zero-copy optimization for reduced memory usage  
✅ Activates Vulkan support for improved graphics rendering  
✅ Enables parallel downloading for faster speeds  
✅ Optimizes memory usage with intelligent tab management  
✅ Creates a specialized wrapper script to prevent duplicate extension installations  

### Improves Privacy
✅ Disables all telemetry and analytics  
✅ Stops background data collection  
✅ Enables experimental ad-blocking features  
✅ Installs privacy-focused extensions by default (uBlock Origin, Dark Reader)  
✅ Applies a clean dark theme for reduced eye strain  

### Streamlines Installation
✅ Automates Brave installation (Stable, Beta, or Nightly variants)  
✅ Configures preferred search engine during setup  
✅ Batch installs recommended extensions  
✅ Creates optimized desktop launcher with persistent settings  
</p>
## 🔍 Search Engine Options

Choose your preferred privacy-respecting search engine:

- **DuckDuckGo** - Privacy-focused but collects some anonymous data
- **Brave Search** - Privacy-focused with independent index
- **SearXNG** - Recommended if self-hosted for maximum privacy
- **Whoogle** - Google results without tracking (self-hosted recommended)
- **Kagi** - Premium search engine with excellent results (paid service)
- **Yandex** - Alternative engine useful behind VPN for certain searches

...or traditional options (not recommended for privacy):
- Google
- Bing

## 🔧 Installation (Linux)
```
git clone https://github.com/nomadxxxx/fast-brave-debloater.git
cd fast-brave-debloater
chmod +x brave_debloat.sh
sudo ./brave_debloat.sh
```
## 🔧 Installation (macOS) (TESTING)
```
git clone https://github.com/nomadxxxx/fast-brave-debloater.git && cd fast-brave-debloater && chmod +x brave_debloat_macos.sh && sudo ./brave_debloat_macos.sh
```
## 📋 Menu Options

### 1. Apply Default Optimizations (Recommended)
- Removes Brave bloat (Rewards/VPN/Wallet/Leo)
- Enables hardware acceleration and rendering optimizations
- Provides full URLs and wide address bar for better usability
- Improves memory usage and performance
- Installs uBlock Origin, Dark Reader, and Dark Theme by default
- Creates a specialized wrapper script to prevent duplicate extension installations

### 2. Install Brave and Apply Customization
- Installs your choi1ce of Brave variant (Stable/Beta/Nightly)
- Applies all default optimizations automatically
- Guides you through search engine selection
- Provides curated extension installation options

### 3-16. Individual Customization Options
- **Change Search Engine** - Select from privacy-focused alternatives
- **Toggle Hardware Acceleration** - Optimize for your hardware
- **Disable Analytics & Data Collection** - Enhanced privacy controls
- **Enable Custom Scriptlets** - Advanced JavaScript injection (for power users)
- **Disable Background Running** - Prevent background processes
- **Toggle Memory Saver** - Automatically free memory from inactive tabs
- **UI Improvements** - Full URLs, wide address bar, bookmarks bar
- **Dashboard Customization** - Clean new tab page with minimal distractions
- **Remove Brave Rewards/VPN/Wallet** - Eliminate cryptocurrency features
- **Toggle Experimental Ad Blocking** - Enhanced ad-blocking capabilities
- **Install Recommended Extensions** - Curated privacy and productivity tools
- **Install Dashboard Customizer** - Replace default new tab page
- **Enable Dark Mode** - System-wide dark theme for Brave
- **Install Browser Theme** - Choose from various visual themes
  
### 17. Revert All Changes
- Completely undo all modifications made by the script

### Menu Screenshot
<p align="center">
  <img src="https://github.com/nomadxxxx/fast-brave-debloater/blob/main/screenshot.png" alt="Fast Brave Debloater Screenshot">
</p>

## 🔄 How the Script Works

The script uses several mechanisms to debloat and optimize Brave:

1. **Policy Files**: Creates and modifies JSON policy files in Brave's managed policies directory to control browser behavior at a system level, making changes persistent across updates.

2. **Preferences Modification**: Directly edits Brave preferences using jq to disable unwanted features and customize the browser experience.

3. **Local State Modification**: Updates the Local State file to enable experimental features like advanced ad blocking.

4. **Custom Wrapper Script**: Creates a specialized wrapper that checks for installed extensions before launching Brave, preventing duplicate installations and ensuring consistent behavior.

5. **Desktop Entry Creation**: Creates a custom desktop entry that launches Brave through the wrapper with optimized parameters.

6. **Extension Installation**: Provides a streamlined interface for installing recommended privacy and productivity extensions.

7. **Policy Enforcement**: Uses enterprise policies to permanently disable unwanted features like Brave Rewards, VPN, Wallet, and AI Chat.

## ⚠️ Important Notes

- Requires root privileges for system-wide changes
- Requires a browser restart after applying changes
- Launch Brave using the "Brave Debloat" shortcut created by the script (visible in application launchers like Rofi etc)
- Custom Scriptlets feature requires manually enabling developer mode in Brave
- Primary testing done on Arch Linux, Fedora and Ubuntu (your mileage may vary)

## 📝 To Do

- [x] Implement experimental ad-blocking feature
- [x] Implement Brave install automation
- [x] Implement auto-install extensions
- [x] Fix install script for Fedora
- [x] Include uBlock Origin, Dark Reader and Dark theme by default
- [x] Implement wrapper script to prevent duplicate extension installations
- [x] Update readme to explain new features
- [ ] Finish and test PowerShell version for Windows
- [ ] Make a script compatible with macOS
- [ ] Add support for Firefox as an alternative browser

