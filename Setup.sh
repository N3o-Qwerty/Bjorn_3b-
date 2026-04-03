#!/bin/bash
# Master Deployment Script - Custom Bjorn Stack for Raspberry Pi 3B+
#
# Generates a suite of helper scripts under ./custom_bjorn_scripts/
# that configure a Bjorn installation for headless (LCD) operation,
# add GPS support, optional WiFi-driver compilation, and a lightweight
# hash-lookup utility.
#
# Usage:
#   chmod +x Setup.sh
#   ./Setup.sh            # generate all helper scripts
#   cd custom_bjorn_scripts/
#   sudo ./setup_env.sh   # run whichever scripts you need
#
# Requirements: bash >= 4, apt-based distro (Raspberry Pi OS recommended)

set -euo pipefail

# ── Colour helpers ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_step()  { echo -e "${CYAN}[*]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*" >&2; }

# ── Global variables ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/custom_bjorn_scripts"

# ── Pre-flight checks ───────────────────────────────────────────────
preflight() {
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        log_error "Bash 4+ is required.  Current version: ${BASH_VERSION}"
        exit 1
    fi
    log_info "Pre-flight checks passed."
}

# ── Helper: write a file and make it executable ─────────────────────
emit_script() {
    local dest="$1"
    log_step "Generating ${dest}..."
    cat > "${OUTPUT_DIR}/${dest}"
    chmod +x "${OUTPUT_DIR}/${dest}"
}

# ── 1. setup_env.sh ─────────────────────────────────────────────────
generate_setup_env() {
    emit_script "setup_env.sh" << 'SCRIPT'
#!/bin/bash
# Installs core runtime dependencies and links web-UI image assets.
set -euo pipefail

BJORN_HOME="/home/bjorn/bjorn"

echo "[*] Installing core dependencies..."
sudo apt-get update -qq
sudo apt-get install -y nmap

echo "[*] Installing Python dependencies for the Orchestrator..."
if [[ -f "${BJORN_HOME}/requirements.txt" ]]; then
    sudo pip3 install -r "${BJORN_HOME}/requirements.txt" --break-system-packages
else
    echo "[!] ${BJORN_HOME}/requirements.txt not found -- skipping pip install."
fi

echo "[*] Bridging Web UI image assets..."
mkdir -p "${BJORN_HOME}/web/static"

LINK_TARGET="${BJORN_HOME}/resources/images"
LINK_NAME="${BJORN_HOME}/web/static/images"

if [[ -L "${LINK_NAME}" ]]; then
    echo "[*] Symlink already exists -- recreating."
    rm -f "${LINK_NAME}"
fi
if [[ -d "${LINK_NAME}" && ! -L "${LINK_NAME}" ]]; then
    echo "[!] ${LINK_NAME} is a real directory -- backing up."
    mv "${LINK_NAME}" "${LINK_NAME}.bak.$(date +%s)"
fi
ln -s "${LINK_TARGET}" "${LINK_NAME}"

echo "[+] Environment setup complete."
SCRIPT
}

# ── 2. patch_hardware.sh ────────────────────────────────────────────
generate_patch_hardware() {
    emit_script "patch_hardware.sh" << 'SCRIPT'
#!/bin/bash
# Bypasses the e-paper display driver so Bjorn runs in headless / LCD mode.
set -euo pipefail

BJORN_HOME="/home/bjorn/bjorn"

echo "[*] Patching EPD Driver..."
mkdir -p "${BJORN_HOME}/resources/waveshare_epd"

cat > "${BJORN_HOME}/resources/waveshare_epd/none.py" << 'PYEOF'
"""Null e-paper driver -- returns safe no-ops for every EPD method."""


class EPD:
    """Stub EPD that silently ignores all display calls."""

    def __init__(self):
        self.width = 250
        self.height = 122

    def __getattr__(self, name):
        return lambda *args, **kwargs: None
PYEOF

echo "[*] Patching Display Thread..."
cat > "${BJORN_HOME}/display.py" << 'PYEOF'
"""Headless display stub -- keeps the thread alive without hardware access."""

import logging
import time


class Display:
    """Minimal display replacement for LCD / headless builds."""

    def __init__(self, shared_data):
        self.logger = logging.getLogger("display.py")
        self.logger.info("Display thread bypassed for LCD mode.")
        self.shared_data = shared_data

    def start(self):
        """Entry point expected by the orchestrator."""
        self.run()

    def run(self):
        """Sleep loop -- keeps the thread alive so the orchestrator
        does not treat the display as crashed."""
        try:
            while True:
                time.sleep(60)
        except KeyboardInterrupt:
            self.logger.info("Display thread shutting down.")


def handle_exit_display(*args, **kwargs):
    """Signal handler stub (no-op)."""
PYEOF

echo "[+] Hardware bypass complete."
SCRIPT
}

# ── 3. build_wifi.sh ────────────────────────────────────────────────
generate_build_wifi() {
    emit_script "build_wifi.sh" << 'SCRIPT'
#!/bin/bash
# Compiles and installs the RTL8852BU USB WiFi driver.
set -euo pipefail

DRIVER_REPO="https://github.com/morrownr/rtl8852bu.git"
DRIVER_DIR="${HOME}/rtl8852bu"

echo "[*] Installing compiler toolchain..."
sudo apt-get update -qq
sudo apt-get install -y build-essential dkms bc git

HEADERS_PKG="linux-headers-$(uname -r)"
if ! dpkg -s "${HEADERS_PKG}" &>/dev/null; then
    echo "[*] Installing kernel headers (${HEADERS_PKG})..."
    sudo apt-get install -y "${HEADERS_PKG}"
else
    echo "[*] Kernel headers already installed."
fi

if [[ -d "${DRIVER_DIR}" ]]; then
    echo "[*] Driver source already cloned -- pulling latest..."
    git -C "${DRIVER_DIR}" pull --ff-only || true
else
    echo "[*] Cloning driver repository..."
    git clone "${DRIVER_REPO}" "${DRIVER_DIR}"
fi

echo "[*] Compiling and installing driver..."
cd "${DRIVER_DIR}"
sudo ./install-driver.sh

echo "[+] Driver installed.  Please unplug and re-plug the USB WiFi adapter."
SCRIPT
}

# ── 4. fix_touch.sh ─────────────────────────────────────────────────
generate_fix_touch() {
    emit_script "fix_touch.sh" << 'SCRIPT'
#!/bin/bash
# Rotates the ADS7846 resistive touchscreen input 180 degrees.
set -euo pipefail

DISPLAY="${DISPLAY:-:0}"
export DISPLAY

# Auto-detect the ADS7846 device id instead of hard-coding it.
DEVICE_ID=$(xinput list --id-only "ADS7846 Touchscreen" 2>/dev/null || true)

if [[ -z "${DEVICE_ID}" ]]; then
    echo "[!] ADS7846 touchscreen not found.  Listing available input devices:"
    xinput list
    echo "[!] Pass the device id as the first argument:  ./fix_touch.sh <device_id>"
    DEVICE_ID="${1:-}"
    if [[ -z "${DEVICE_ID}" ]]; then
        echo "[-] No device id provided -- aborting."
        exit 1
    fi
fi

echo "[*] Rotating touch input (device ${DEVICE_ID}) by 180 degrees..."
xinput set-prop "${DEVICE_ID}" "Coordinate Transformation Matrix" -1 0 1 0 -1 1 0 0 1

echo "[+] Touchscreen rotation applied."
SCRIPT
}

# ── 5. setup_gps.sh ─────────────────────────────────────────────────
generate_setup_gps() {
    emit_script "setup_gps.sh" << 'SCRIPT'
#!/bin/bash
# Configures GPSD for U-Blox 7 GPS receivers on the Raspberry Pi.
set -euo pipefail

echo "[*] Installing GPSD and client utilities..."
sudo apt-get update -qq
sudo apt-get install -y gpsd gpsd-clients python3-gps

echo "[*] Writing GPSD configuration..."
sudo tee /etc/default/gpsd > /dev/null << 'CONF'
# Configuration for U-Blox 7 GPS receiver
START_DAEMON="true"
GPSD_OPTIONS="-n"
DEVICES="/dev/ttyACM0 /dev/ttyUSB0"
USBAUTO="true"
GPSD_SOCKET="/var/run/gpsd.sock"
CONF

echo "[*] Enabling and restarting GPSD service..."
sudo systemctl enable gpsd
sudo systemctl restart gpsd

echo "[+] GPS configured.  Run 'cgps -s' to verify satellite lock."
SCRIPT
}

# ── 6. crackstation_sync.py ─────────────────────────────────────────
generate_crackstation_sync() {
    emit_script "crackstation_sync.py" << 'SCRIPT'
#!/usr/bin/env python3
"""Lightweight hash-lookup utility.

Walks the Bjorn loot directory for files containing MD5 hashes and
attempts to resolve them via a public online database.

Usage:
    ./crackstation_sync.py                        # use defaults
    ./crackstation_sync.py --loot-dir /some/path  # custom loot path
"""

import argparse
import logging
import os
import re
import sys
import time

try:
    import requests
except ImportError:
    sys.exit("[!] 'requests' is required.  Install with: pip3 install requests")

LOOT_DIR_DEFAULT = "/home/bjorn/bjorn/data/output"
CRACKED_LOG_DEFAULT = "/home/bjorn/bjorn/data/cracked_hashes.txt"
HASH_API_URL = "https://www.nitrxgen.net/md5db/{hash}"
REQUEST_TIMEOUT = 10  # seconds
REQUEST_DELAY = 1.0   # seconds between API calls (rate-limit courtesy)

MD5_PATTERN = re.compile(r"\b[a-fA-F0-9]{32}\b")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description="Bjorn MD5 hash-lookup utility")
    parser.add_argument(
        "--loot-dir",
        default=LOOT_DIR_DEFAULT,
        help=f"Directory to scan for loot files (default: {LOOT_DIR_DEFAULT})",
    )
    parser.add_argument(
        "--cracked-log",
        default=CRACKED_LOG_DEFAULT,
        help=f"File to append cracked results to (default: {CRACKED_LOG_DEFAULT})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="List discovered hashes without querying the API",
    )
    return parser.parse_args()


def check_hash_online(hash_value):
    """Query the public MD5 database.  Returns plaintext or None."""
    url = HASH_API_URL.format(hash=hash_value)
    try:
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        text = response.text.strip()
        if text:
            return text
    except requests.RequestException as exc:
        log.warning("API request failed for %s: %s", hash_value, exc)
    return None


def collect_hashes(loot_dir):
    """Walk *loot_dir* and return a dict of unique MD5 hashes to source file."""
    hashes = {}
    for root, _dirs, files in os.walk(loot_dir):
        for filename in files:
            if not filename.endswith((".txt", ".csv", ".log")):
                continue
            filepath = os.path.join(root, filename)
            try:
                with open(filepath, "r", errors="ignore") as fh:
                    for match in MD5_PATTERN.finditer(fh.read()):
                        h = match.group().lower()
                        hashes.setdefault(h, filepath)
            except OSError as exc:
                log.warning("Could not read %s: %s", filepath, exc)
    return hashes


def main():
    args = parse_args()

    if not os.path.isdir(args.loot_dir):
        log.error("Loot directory not found: %s", args.loot_dir)
        sys.exit(1)

    hashes = collect_hashes(args.loot_dir)
    if not hashes:
        log.info("No MD5 hashes found in %s", args.loot_dir)
        return

    log.info("Found %d unique MD5 hash(es) to look up.", len(hashes))

    if args.dry_run:
        for h, src in hashes.items():
            log.info("  %s  (from %s)", h, os.path.basename(src))
        return

    cracked = 0
    for h, src in hashes.items():
        plaintext = check_hash_online(h)
        if plaintext:
            cracked += 1
            log.info("CRACKED  %s -> %s", h, plaintext)
            os.makedirs(os.path.dirname(args.cracked_log), exist_ok=True)
            with open(args.cracked_log, "a") as log_file:
                log_file.write(
                    f"{h}:{plaintext} (source: {os.path.basename(src)})\n"
                )
        else:
            log.info("NOT FOUND  %s", h)
        time.sleep(REQUEST_DELAY)

    log.info("Done. %d / %d hash(es) cracked.", cracked, len(hashes))


if __name__ == "__main__":
    main()
SCRIPT
}

# ── 7. config_patch.json ────────────────────────────────────────────
generate_config_patch() {
    log_step "Generating config_patch.json..."
    cat > "${OUTPUT_DIR}/config_patch.json" << 'JSON'
{
  "__title_Bjorn__": "Settings",
  "epd_type": "none",
  "__title_network__": "Network",
  "network_interface": "wlan1",
  "mac_scan_blacklist": [
    "b8:27:eb:fd:76:86"
  ]
}
JSON
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "=============================================="
    echo "  Bjorn 3B+ Custom Stack - Script Generator"
    echo "=============================================="
    echo ""

    preflight

    mkdir -p "${OUTPUT_DIR}"

    generate_setup_env
    generate_patch_hardware
    generate_build_wifi
    generate_fix_touch
    generate_setup_gps
    generate_crackstation_sync
    generate_config_patch

    echo ""
    log_info "All scripts generated in ${OUTPUT_DIR}/"
    echo ""
    echo "  Recommended run order (with sudo where needed):"
    echo "    1.  sudo ./setup_env.sh          # core deps + web assets"
    echo "    2.  sudo ./patch_hardware.sh     # EPD / display bypass"
    echo "    3.  sudo ./build_wifi.sh         # RTL8852BU driver (optional)"
    echo "    4.       ./fix_touch.sh          # touchscreen rotation (optional)"
    echo "    5.  sudo ./setup_gps.sh          # GPS receiver setup (optional)"
    echo "    6.       ./crackstation_sync.py  # hash-lookup utility (optional)"
    echo ""
}

main "$@"
