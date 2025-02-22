![alt text](https://github.com/nomadxxxx/fast-brave-debloater/blob/main/logo.png) 

A powerful optimization script that strips Brave Browser of bloat and enhances performance. Say goodbye to crypto popups, VPN promotions, and unnecessary features!

# Removes Brave Bloat

❌ No more crypto wallet popups

❌ No more VPN promotions

❌ No more Brave Rewards notifications

❌ No more AI Chat suggestions

❌ No more unnecessary background processes

## Improves Performance

Enables GPU acceleration for smoother browsing

Implements zero-copy optimization

Activates Vulkan support

Enables parallel downloading for faster speeds

Optimizes memory usage

## Enhances Privacy

Disables telemetry

Removes analytics

Stops background data collection

Disable Brave Sync (optional but recommended)

### Customizes for security

Script allows you to choose your preferred privacy-respecting search engine:

DuckDuckGo
SearXNG (recommended)
Whoogle (good, but not as good as searXNG)
Kagi (good, but expensive)

...or worse options
Google (not recommended)
Bing (not recommended)

### 🔧 Installation
```
git clone https://github.com/nomadxx/fast-brave-debloater/brave-debloat.git
cd brave-debloat
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


⚠️ Important Notes
Requires root privileges. Requires a browser restart. To launch Brave after running the Brave Debloated you should use the Brave Debloater shortcut (adds a brave-debloat.desktop you should see in Rofi etc..

Custom Scriptlets requires you enable dev mode manually. 

I've only tested this on Arch and using an Nvidia GPU so how this script works with AMD cards I'm not 100%.
