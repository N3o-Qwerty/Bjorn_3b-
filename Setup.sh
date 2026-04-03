#!/bin/bash
# Master Deployment Script - Custom Bjorn Stack

mkdir -p custom_bjorn_scripts
cd custom_bjorn_scripts

echo "[*] Generating setup_env.sh..."
cat << 'EOF' > setup_env.sh
#!/bin/bash
echo "[*] Installing core dependencies..."
sudo apt update && sudo apt install -y nmap
echo "[*] Fixing root Python dependencies for the Orchestrator..."
cd /home/bjorn/bjorn
sudo pip3 install -r requirements.txt --break-system-packages
echo "[*] Bridging Web UI Image Assets..."
mkdir -p /home/bjorn/bjorn/web/static
rm -rf /home/bjorn/bjorn/web/static/images
ln -s /home/bjorn/bjorn/resources/images /home/bjorn/bjorn/web/static/images
echo "[*] Environment setup complete."
EOF

echo "[*] Generating patch_hardware.sh..."
cat << 'EOF' > patch_hardware.sh
#!/bin/bash
echo "[*] Patching EPD Driver..."
mkdir -p /home/bjorn/bjorn/resources/waveshare_epd
cat << "INNER_EOF" > /home/bjorn/bjorn/resources/waveshare_epd/none.py
class EPD:
    def __init__(self):
        self.width = 250
        self.height = 122
    def __getattr__(self, name):
        return lambda *args, **kwargs: None
INNER_EOF

echo "[*] Patching Display Thread..."
cat << "INNER_EOF" > /home/bjorn/bjorn/display.py
import time
import logging
class Display:
    def __init__(self, shared_data):
        self.logger = logging.getLogger("display.py")
        self.logger.info("Display thread bypassed for LCD mode.")
        self.shared_data = shared_data
    def start(self):
        self.run()
    def run(self):
        try:
            while True:
                time.sleep(60)
        except KeyboardInterrupt:
            pass
def handle_exit_display(*args, **kwargs):
    pass
INNER_EOF
echo "[*] Hardware bypass complete."
EOF

echo "[*] Generating build_wifi.sh..."
cat << 'EOF' > build_wifi.sh
#!/bin/bash
echo "[*] Installing compiler tools..."
sudo apt update && sudo apt install -y build-essential dkms bc linux-headers-$(uname -r) git
echo "[*] Cloning driver repository..."
cd ~
git clone https://github.com/morrownr/rtl8852bu.git
cd rtl8852bu
echo "[*] Compiling driver..."
sudo ./install-driver.sh
echo "[*] Driver built. Please unplug and re-plug the USB adapter."
EOF

echo "[*] Generating fix_touch.sh..."
cat << 'EOF' > fix_touch.sh
#!/bin/bash
echo "[*] Rotating ADS7846 touch axis 180 degrees..."
DISPLAY=:0 xinput set-prop 6 "Coordinate Transformation Matrix" -1 0 1 0 -1 1 0 0 1
EOF

echo "[*] Generating setup_gps.sh..."
cat << 'EOF' > setup_gps.sh
#!/bin/bash
echo "[*] Installing GPSD and dependencies..."
sudo apt update && sudo apt install -y gpsd gpsd-clients python3-gps
echo "[*] Configuring GPSD for the U-Blox 7 Receiver..."
sudo bash -c 'cat << INNER_EOF > /etc/default/gpsd
START_DAEMON="true"
GPSD_OPTIONS="-n"
DEVICES="/dev/ttyACM0 /dev/ttyUSB0"
USBAUTO="true"
GPSD_SOCKET="/var/run/gpsd.sock"
INNER_EOF'
echo "[*] Enabling and restarting GPSD service..."
sudo systemctl enable gpsd
sudo systemctl restart gpsd
echo "[*] GPS Add-on configured. Run 'cgps -s' to verify satellite lock."
EOF

echo "[*] Generating crackstation_sync.py..."
cat << 'EOF' > crackstation_sync.py
#!/usr/bin/env python3
import os
import requests
import re
import time

LOOT_DIR = "/home/bjorn/bjorn/data/output"
CRACKED_LOG = "/home/bjorn/bjorn/data/cracked_hashes.txt"

def check_hash_online(hash_value):
    print(f"[*] Syncing hash to online DB: {hash_value}")
    try:
        response = requests.get(f"http://www.nitrxgen.net/md5db/{hash_value}", timeout=5)
        if response.status_code == 200 and response.text:
            return response.text
    except requests.RequestException:
        pass
    return None

def main():
    print("[*] Starting Hash Sync Engine...")
    if not os.path.exists(LOOT_DIR):
        print("[-] Loot directory not found.")
        return

    for root, dirs, files in os.walk(LOOT_DIR):
        for file in files:
            if file.endswith(".txt") or file.endswith(".csv"):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', errors='ignore') as f:
                    content = f.read()
                    hashes = re.findall(r'\b[a-fA-F0-9]{32}\b', content)
                    for h in set(hashes):
                        plaintext = check_hash_online(h)
                        if plaintext:
                            print(f"[+] CRACKED! {h} -> {plaintext}")
                            with open(CRACKED_LOG, 'a') as log:
                                log.write(f"{h}:{plaintext} (Found in {file})\n")
                        else:
                            print(f"[-] Not found in online DB: {h}")
                        time.sleep(1)

if __name__ == "__main__":
    main()
EOF

echo "[*] Generating config_patch.json..."
cat << 'EOF' > config_patch.json
{
  "__title_Bjorn__": "Settings",
  "epd_type": "none",
  "__title_network__": "Network",
  "network_interface": "wlan1",
  "mac_scan_blacklist": [
    "b8:27:eb:fd:76:86"
  ]
}
EOF

chmod +x *.sh
chmod +x *.py
echo "[+] All custom Bjorn scripts successfully generated in ./custom_bjorn_scripts/"
