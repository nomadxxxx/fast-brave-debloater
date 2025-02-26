![alt text](https://github.com/nomadxxxx/fast-brave-debloater/blob/main/logo.png) 

A powerful optimization script that strips Brave Browser of bloat and enhances performance. Say goodbye to Brave crypto, VPN, Ad bullshit and unnecessary features! The script also automates fresh Brave installs letting you pick from Stable, Beta and Nightly variants.

# Removes Brave Bloat

❌ No more crypto wallet

❌ No more Brave VPN promotions

❌ No more Brave Rewards notifications

❌ No more LeoAI Chat suggestions

❌ No more unnecessary background processes

## Improves Performance

✅ Enables GPU acceleration for smoother browsing

✅ Implements zero-copy optimization

✅ Activates Vulkan support

✅ Enables parallel downloading for faster speeds

✅ Optimizes memory usage

## Enhances Privacy

✅ Disables telemetry

✅ Removes analytics

✅ Stops background data collection

✅ Disable Brave Sync (optional but recommended)

### Customizes for security

Script allows you to choose your preferred privacy-respecting search engine:

- DuckDuckGo (privacy focused but collects data)
- Brave Search (privacy focused but collects data)
- SearXNG (recommended if you self-host)
- Whoogle (recommended if you self-host, but not as good as searXNG)
- Kagi (very good engine, but expensive)
- Yandex (ok for when doing sensitive searching behind VPN or 9000 proxy)

...or worse options
- Google (not recommended)
- Bing (not recommended)

### 🔧 Installation
```
git clone https://github.com/nomadxxxx/fast-brave-debloater.git
cd fast-brave-debloater
chmod +x brave_debloat.sh
sudo ./brave_debloat.sh
```
![alt text](https://github.com/nomadxxxx/fast-brave-debloater/blob/main/screenshot.png) 

### Menu Options
Apply Default Optimizations (recommended)
- Removes Brave bloat (e.g. Rewards/VPN/Wallet/Leo)
- enables hardware rendering
- provides full URLs, wide address bar
- improves memory usage
  
Select specific customizations:
- Change Search Engine
  --  DuckDuckGo (Recommended)
  --  SearXNG (you must manually enter your SearXNG address)
  --  Whoogle (you must manually enter your Whoogle address)
  --  Google, Bing 
- Toggle Hardware Acceleration
- Disable Analytics & Data Collection
  -- Reudces background analytics
  -- Removes telemetry
- Enable Custom Scriptlets (Advanced)
  -- For advanced users only, allows custom JavaScript injection:
  -- can be used to block resource-heavy elements
- Disable Background Running (Warning may be unstable)
  -- Prevents Brave from running in background
- Disable Brave Sync
- Disable Brave Rewards/VPN/Wallet
- Toggle Memory Saver
  --Automatically frees memory from inactive tabs
- Enable experimental ad-blocking
- Select from recommended extensions (ublock, protonpass, darkreader etc) to install

### To do
- [X] Implement experimental ad-blocking feature
- [X] Implement Brave install automation
- [ ] Finish and test powershell version for windows
- [ ] Make a script compatible with macOS

### How the Script Works
The script uses several mechanisms to debloat and optimize Brave:
1. Policy Files: Creates and modifies JSON policy files in Brave's managed policies directory to control browser behavior at a system level (basically creates an enterprise policy to make changes persistent across Brave updates etc).
2. Preferences Modification: Directly edits the Brave preferences file using jq to disable unwanted features and customize the browser experience.
3.Local State Modification: Updates the Local State file to enable experimental features like advanced ad blocking.
4. Desktop Entry Creation: Creates a custom desktop entry (brave-debloat.desktop) that launches Brave with optimized parameters/flags.
5. Extension Installation: Provides a streamlined interface for installing recommended privacy and productivity extensions (note that this will not auto-install because of Brave security policies but it comes close to auto-installation).
6. Policy Enforcement: Uses enterprise policies to permanently disable unwanted features like Brave Rewards, VPN, Wallet, and AI Chat.


⚠️ Important Notes
- Requires root privileges. 
- Requires a browser restart. 
To launch Brave after running the Brave Debloated you should use the Brave Debloater shortcut (adds a **brave-debloat.desktop** you should see in Rofi etc..
- **Custom Scriptlets requires you enable dev mode manually. ** if you are unsure how to enter dev mode do not enable this feature.

I've only tested this on Arch and using an Nvidia GPU so how this script works with AMD cards I'm not 100%.
