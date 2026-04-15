#!/bin/bash

# ==============================================================================
# Quectel + EIOT Club Auto-Setup for Ubuntu 24.04 on Raspberry Pi 5
# ==============================================================================

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run this script with sudo."
  exit 1
fi

echo "🚀 Starting Quectel + EIOT Setup..."

# 2. Fix Raspberry Pi 5 USB Power Limit (Requires Reboot if changed)
CONFIG_FILE="/boot/firmware/config.txt"
if grep -q "usb_max_current_enable=1" "$CONFIG_FILE"; then
    echo "✅ RPi5 USB power limit already maximized."
else
    echo "⚡ Increasing RPi5 USB power limit to 1.6A..."
    echo "usb_max_current_enable=1" >> "$CONFIG_FILE"
    NEEDS_REBOOT=true
fi

# 3. Install required management tools
echo "📦 Installing NetworkManager and ModemManager..."
apt update -yq
apt install -yq network-manager modemmanager

# Ensure services are running
systemctl enable --now ModemManager
systemctl enable --now NetworkManager

# 4. Wait for the modem to be detected
echo "🔍 Searching for Quectel modem..."
MODEM_INDEX=""
for i in {1..15}; do
    MODEM_INDEX=$(mmcli -L | grep -i "Modem" | head -n1 | awk '{print $1}' | awk -F'/' '{print $NF}')
    if [ -n "$MODEM_INDEX" ]; then
        echo "✅ Modem found at index: $MODEM_INDEX"
        break
    fi
    sleep 2
done

if [ -z "$MODEM_INDEX" ]; then
    echo "❌ No modem detected via mmcli. Check USB connection."
    exit 1
fi

# 5. Force modem to use SIM Slot 1 (Crucial for Quectel EG25-G USB adapters)
echo "🔀 Forcing modem to check physical SIM Slot 1..."
mmcli -m "$MODEM_INDEX" --set-primary-sim-slot=1
echo "⏳ Waiting 15 seconds for modem to re-initialize SIM..."
sleep 15

# 6. Clean up old connections
echo "🧹 Clearing old EIOT network profiles..."
nmcli connection delete eiot-lte 2>/dev/null

# 7. Create the NetworkManager Profile for EIOT Club
echo "🌐 Creating NetworkManager profile for EIOT (APN: mobile)..."
nmcli connection add type gsm \
    ifname "cdc-wdm0" \
    con-name eiot-lte \
    apn mobile \
    gsm.home-only no \
    ipv4.route-metric 10 \
    connection.autoconnect yes

# 8. Bring the connection online
echo "🚀 Activating connection..."
nmcli connection up eiot-lte

# 9. Final Status Check
echo "----------------------------------------------------"
echo "📊 Setup Complete! Current IP addresses on wwan0:"
ip -4 addr show wwan0 | grep inet

if [ "$NEEDS_REBOOT" = true ]; then
    echo "----------------------------------------------------"
    echo "⚠️  IMPORTANT: The RPi5 USB power limit was updated."
    echo "You MUST REBOOT now for the power changes to take effect,"
    echo "otherwise the modem may disconnect under heavy load."
    echo "Run: sudo reboot"
fi
