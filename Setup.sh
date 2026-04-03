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
#   ./Setup.sh                        # generate all helper scripts
#   ./Setup.sh --only env,gps,health  # generate selected scripts only
#   ./Setup.sh --help                 # show usage information
#   cd custom_bjorn_scripts/
#   sudo ./setup_env.sh               # run whichever scripts you need
#
# Requirements: bash >= 4, apt-based distro (Raspberry Pi OS recommended)

set -euo pipefail

# ── Version ──────────────────────────────────────────────────────────
VERSION="2.0.0"

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

# ── Usage / help ─────────────────────────────────────────────────────
usage() {
    cat << EOF
Bjorn 3B+ Custom Stack - Script Generator  v${VERSION}

Usage:
  ./Setup.sh [OPTIONS]

Options:
  -h, --help        Show this help message and exit
  -v, --version     Print version and exit
  --only LIST       Comma-separated list of scripts to generate.
                    Valid names: env, hardware, wifi, touch, gps,
                    crackstation, config, teardown, apply_config,
                    gps_logger, ble_scanner, health
                    Example: --only env,gps,health

If --only is not specified, all scripts are generated.

Generated scripts are placed in: ./custom_bjorn_scripts/

Run Order (with sudo where needed):
  1. sudo ./setup_env.sh          # core deps + web assets
  2. sudo ./patch_hardware.sh     # EPD / display bypass
  3. sudo ./build_wifi.sh         # RTL8852BU driver       (optional)
  4.      ./fix_touch.sh          # touchscreen rotation   (optional)
  5. sudo ./setup_gps.sh          # GPS receiver setup     (optional)
  6.      ./crackstation_sync.py  # hash-lookup utility    (optional)
  7. sudo ./apply_config.sh       # apply config overrides (optional)
  8.      ./gps_logger.py         # GPS coordinate logger  (optional)
  9. sudo ./ble_scanner.sh        # BLE device scanner     (optional)
 10.      ./health_check.sh       # system health monitor  (optional)
 11. sudo ./teardown.sh           # uninstall / rollback   (optional)
EOF
}

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

    # Validate the file was written and is non-empty
    if [[ ! -s "${OUTPUT_DIR}/${dest}" ]]; then
        log_error "Failed to write ${dest} (file is empty or missing)."
        exit 1
    fi
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

Walks the Bjorn loot directory for files containing MD5, SHA1, and SHA256
hashes and attempts to resolve them via public online databases.

Usage:
    ./crackstation_sync.py                        # use defaults
    ./crackstation_sync.py --loot-dir /some/path  # custom loot path
    ./crackstation_sync.py --hash-types md5,sha1  # specific hash types
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
REQUEST_TIMEOUT = 10  # seconds
REQUEST_DELAY = 1.0   # seconds between API calls (rate-limit courtesy)

# Hash patterns and their corresponding API endpoints
HASH_TYPES = {
    "md5": {
        "pattern": re.compile(r"\b[a-fA-F0-9]{32}\b"),
        "api_url": "https://www.nitrxgen.net/md5db/{hash}",
        "label": "MD5",
    },
    "sha1": {
        "pattern": re.compile(r"\b[a-fA-F0-9]{40}\b"),
        "api_url": None,  # no free plaintext API; collect only
        "label": "SHA1",
    },
    "sha256": {
        "pattern": re.compile(r"\b[a-fA-F0-9]{64}\b"),
        "api_url": None,  # no free plaintext API; collect only
        "label": "SHA256",
    },
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Bjorn hash-lookup utility (MD5, SHA1, SHA256)"
    )
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
    parser.add_argument(
        "--hash-types",
        default="md5,sha1,sha256",
        help="Comma-separated list of hash types to look for (default: md5,sha1,sha256)",
    )
    return parser.parse_args()


def check_hash_online(hash_value, hash_type):
    """Query a public hash database.  Returns plaintext or None."""
    config = HASH_TYPES.get(hash_type)
    if not config:
        return None
    api_url = config["api_url"]
    if api_url is None:
        return None  # no API available for this hash type
    url = api_url.format(hash=hash_value)
    try:
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        text = response.text.strip()
        if text:
            return text
    except requests.RequestException as exc:
        log.warning("API request failed for %s: %s", hash_value, exc)
    return None


def collect_hashes(loot_dir, hash_types):
    """Walk *loot_dir* and return a dict mapping (hash, type) to source file."""
    hashes = {}
    for root, _dirs, files in os.walk(loot_dir):
        for filename in files:
            if not filename.endswith((".txt", ".csv", ".log")):
                continue
            filepath = os.path.join(root, filename)
            try:
                with open(filepath, "r", errors="ignore") as fh:
                    content = fh.read()
                    for ht in hash_types:
                        config = HASH_TYPES.get(ht)
                        if not config:
                            continue
                        for match in config["pattern"].finditer(content):
                            h = match.group().lower()
                            hashes.setdefault((h, ht), filepath)
            except OSError as exc:
                log.warning("Could not read %s: %s", filepath, exc)
    return hashes


def main():
    args = parse_args()

    requested_types = [t.strip().lower() for t in args.hash_types.split(",")]
    valid_types = [t for t in requested_types if t in HASH_TYPES]
    if not valid_types:
        log.error(
            "No valid hash types specified.  Choose from: %s",
            ", ".join(HASH_TYPES.keys()),
        )
        sys.exit(1)

    if not os.path.isdir(args.loot_dir):
        log.error("Loot directory not found: %s", args.loot_dir)
        sys.exit(1)

    hashes = collect_hashes(args.loot_dir, valid_types)
    if not hashes:
        log.info("No hashes found in %s", args.loot_dir)
        return

    log.info(
        "Found %d unique hash(es) to look up (%s).",
        len(hashes),
        ", ".join(valid_types),
    )

    if args.dry_run:
        for (h, ht), src in hashes.items():
            label = HASH_TYPES[ht]["label"]
            log.info("  [%s] %s  (from %s)", label, h, os.path.basename(src))
        return

    cracked = 0
    for (h, ht), src in hashes.items():
        label = HASH_TYPES[ht]["label"]
        config = HASH_TYPES[ht]
        if config["api_url"] is None:
            log.info("COLLECTED [%s] %s  (from %s) -- no online lookup available", label, h, os.path.basename(src))
            os.makedirs(os.path.dirname(args.cracked_log), exist_ok=True)
            with open(args.cracked_log, "a") as log_file:
                log_file.write(
                    f"[{label}] {h}:??? (source: {os.path.basename(src)})\n"
                )
            continue
        plaintext = check_hash_online(h, ht)
        if plaintext:
            cracked += 1
            log.info("CRACKED  [%s] %s -> %s", label, h, plaintext)
            os.makedirs(os.path.dirname(args.cracked_log), exist_ok=True)
            with open(args.cracked_log, "a") as log_file:
                log_file.write(
                    f"[{label}] {h}:{plaintext} (source: {os.path.basename(src)})\n"
                )
        else:
            log.info("NOT FOUND  [%s] %s", label, h)
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

# ── 8. teardown.sh ──────────────────────────────────────────────────
generate_teardown() {
    emit_script "teardown.sh" << 'SCRIPT'
#!/bin/bash
# Uninstall / rollback script for the Bjorn 3B+ custom stack.
# Reverses changes made by the other setup scripts.
set -euo pipefail

BJORN_HOME="/home/bjorn/bjorn"
DRIVER_DIR="${HOME}/rtl8852bu"

echo ""
echo "=============================================="
echo "  Bjorn 3B+ Custom Stack - Teardown"
echo "=============================================="
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*" >&2; }

confirm() {
    local prompt="$1"
    read -r -p "$(echo -e "${YELLOW}[?]${NC} ${prompt} [y/N]: ")" answer
    [[ "${answer}" =~ ^[Yy]$ ]]
}

if confirm "Remove EPD stub and display bypass?"; then
    if [[ -f "${BJORN_HOME}/resources/waveshare_epd/none.py" ]]; then
        rm -f "${BJORN_HOME}/resources/waveshare_epd/none.py"
        log_info "Removed EPD stub (none.py)."
    else
        log_warn "EPD stub not found -- skipping."
    fi
    if [[ -f "${BJORN_HOME}/display.py" ]]; then
        rm -f "${BJORN_HOME}/display.py"
        log_info "Removed display bypass."
        log_warn "You may need to restore the original display.py from the Bjorn repo."
    fi
fi

if confirm "Remove web-UI image symlink?"; then
    LINK_NAME="${BJORN_HOME}/web/static/images"
    if [[ -L "${LINK_NAME}" ]]; then
        rm -f "${LINK_NAME}"
        log_info "Removed symlink: ${LINK_NAME}"
        BACKUP=$(ls -1t "${LINK_NAME}".bak.* 2>/dev/null | head -1 || true)
        if [[ -n "${BACKUP}" ]]; then
            mv "${BACKUP}" "${LINK_NAME}"
            log_info "Restored backup: ${BACKUP}"
        fi
    else
        log_warn "Symlink not found -- skipping."
    fi
fi

if confirm "Remove RTL8852BU WiFi driver?"; then
    if [[ -d "${DRIVER_DIR}" ]]; then
        cd "${DRIVER_DIR}"
        if [[ -f "remove-driver.sh" ]]; then
            sudo ./remove-driver.sh || log_warn "Driver removal script failed."
        else
            log_warn "remove-driver.sh not found in ${DRIVER_DIR}."
        fi
        cd "${HOME}"
        rm -rf "${DRIVER_DIR}"
        log_info "Driver source removed."
    else
        log_warn "Driver source directory not found -- skipping."
    fi
fi

if confirm "Remove GPSD configuration and disable service?"; then
    if systemctl is-active --quiet gpsd 2>/dev/null; then
        sudo systemctl stop gpsd
        sudo systemctl disable gpsd
        log_info "GPSD service stopped and disabled."
    fi
    if [[ -f /etc/default/gpsd ]]; then
        sudo rm -f /etc/default/gpsd
        log_info "Removed /etc/default/gpsd."
    fi
fi

if confirm "Remove applied config overrides from shared_data.json?"; then
    CONFIG_FILE="${BJORN_HOME}/data/shared_data.json"
    if [[ -f "${CONFIG_FILE}.bak" ]]; then
        cp "${CONFIG_FILE}.bak" "${CONFIG_FILE}"
        log_info "Restored config from backup."
    else
        log_warn "No config backup found.  Manual restoration may be needed."
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if confirm "Remove all generated scripts in ${SCRIPT_DIR}?"; then
    rm -rf "${SCRIPT_DIR}"
    log_info "Generated scripts removed."
fi

echo ""
log_info "Teardown complete."
echo ""
SCRIPT
}

# ── 9. apply_config.sh ──────────────────────────────────────────────
generate_apply_config() {
    emit_script "apply_config.sh" << 'SCRIPT'
#!/bin/bash
# Merges config_patch.json into Bjorn's shared_data.json configuration.
set -euo pipefail

BJORN_HOME="/home/bjorn/bjorn"
CONFIG_FILE="${BJORN_HOME}/data/shared_data.json"
PATCH_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config_patch.json"

if [[ ! -f "${PATCH_FILE}" ]]; then
    echo "[-] config_patch.json not found at ${PATCH_FILE}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "[*] Installing jq..."
    sudo apt-get update -qq
    sudo apt-get install -y jq
fi

if [[ -f "${CONFIG_FILE}" ]]; then
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.bak"
    echo "[*] Backed up existing config to ${CONFIG_FILE}.bak"

    echo "[*] Merging config_patch.json into shared_data.json..."
    jq -s '.[0] * .[1]' "${CONFIG_FILE}" "${PATCH_FILE}" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
else
    echo "[!] ${CONFIG_FILE} not found -- creating from patch."
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    cp "${PATCH_FILE}" "${CONFIG_FILE}"
fi

echo "[+] Configuration applied successfully."
echo "[*] Review: cat ${CONFIG_FILE}"
SCRIPT
}

# ── 10. gps_logger.py ───────────────────────────────────────────────
generate_gps_logger() {
    emit_script "gps_logger.py" << 'SCRIPT'
#!/usr/bin/env python3
"""GPS coordinate logger for Bjorn.

Reads GPS data from GPSD and logs timestamped coordinates to a CSV file.
Integrates with Bjorn's data directory for loot correlation.

Usage:
    ./gps_logger.py                              # default output
    ./gps_logger.py --output /path/to/log.csv    # custom output file
    ./gps_logger.py --interval 5                 # log every 5 seconds
    ./gps_logger.py --duration 3600              # run for 1 hour
"""

import argparse
import csv
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone

try:
    from gps import gps, WATCH_ENABLE, WATCH_NEWSTYLE
except ImportError:
    sys.exit(
        "[!] 'python3-gps' is required.  Install with: "
        "sudo apt-get install python3-gps"
    )

DEFAULT_OUTPUT = "/home/bjorn/bjorn/data/gps_log.csv"
DEFAULT_INTERVAL = 10
CSV_FIELDS = [
    "timestamp",
    "latitude",
    "longitude",
    "altitude_m",
    "speed_mps",
    "heading",
    "satellites",
    "fix_mode",
]

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

running = True


def handle_signal(_sig, _frame):
    global running
    running = False
    log.info("Shutdown signal received.")


def parse_args():
    parser = argparse.ArgumentParser(description="Bjorn GPS coordinate logger")
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help=f"CSV output file (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=DEFAULT_INTERVAL,
        help=f"Seconds between log entries (default: {DEFAULT_INTERVAL})",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=0,
        help="Total seconds to run (0 = indefinite, default: 0)",
    )
    return parser.parse_args()


def get_fix_mode_label(mode):
    """Convert numeric GPS fix mode to a human-readable label."""
    labels = {0: "No data", 1: "No fix", 2: "2D fix", 3: "3D fix"}
    return labels.get(mode, f"Unknown ({mode})")


def main():
    args = parse_args()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    write_header = not os.path.exists(args.output)

    log.info("Connecting to GPSD...")
    session = gps(mode=WATCH_ENABLE | WATCH_NEWSTYLE)

    log.info("Logging GPS data to %s (every %ds)", args.output, args.interval)
    start_time = time.time()
    entries = 0

    with open(args.output, "a", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=CSV_FIELDS)
        if write_header:
            writer.writeheader()

        while running:
            try:
                report = session.next()

                if report.get("class") != "TPV":
                    continue

                lat = report.get("lat", None)
                lon = report.get("lon", None)
                if lat is None or lon is None:
                    continue

                row = {
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "latitude": lat,
                    "longitude": lon,
                    "altitude_m": report.get("alt", ""),
                    "speed_mps": report.get("speed", ""),
                    "heading": report.get("track", ""),
                    "satellites": report.get("nSat", ""),
                    "fix_mode": get_fix_mode_label(report.get("mode", 0)),
                }
                writer.writerow(row)
                csvfile.flush()
                entries += 1
                log.info(
                    "Fix: %.6f, %.6f  alt=%.1fm  spd=%.1fm/s",
                    lat,
                    lon,
                    report.get("alt", 0),
                    report.get("speed", 0),
                )

                time.sleep(args.interval)

                if args.duration > 0:
                    elapsed = time.time() - start_time
                    if elapsed >= args.duration:
                        log.info("Duration limit reached (%ds).", args.duration)
                        break

            except StopIteration:
                log.warning("GPSD connection lost.  Retrying in 5s...")
                time.sleep(5)
                session = gps(mode=WATCH_ENABLE | WATCH_NEWSTYLE)
            except KeyError:
                continue

    log.info("Logged %d GPS entries to %s", entries, args.output)


if __name__ == "__main__":
    main()
SCRIPT
}

# ── 11. ble_scanner.sh ──────────────────────────────────────────────
generate_ble_scanner() {
    emit_script "ble_scanner.sh" << 'SCRIPT'
#!/bin/bash
# Bluetooth Low Energy (BLE) device scanner for Raspberry Pi 3B+.
# Scans for nearby BLE devices and logs results to Bjorn's data directory.
set -euo pipefail

BJORN_HOME="/home/bjorn/bjorn"
OUTPUT_DIR="${BJORN_HOME}/data/ble_scans"
SCAN_DURATION="${1:-10}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_step()  { echo -e "${CYAN}[*]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*" >&2; }

if ! command -v bluetoothctl &>/dev/null; then
    log_step "Installing bluetooth utilities..."
    sudo apt-get update -qq
    sudo apt-get install -y bluez bluetooth
fi

if ! command -v hcitool &>/dev/null; then
    log_error "hcitool not found.  Install bluez: sudo apt-get install bluez"
    exit 1
fi

if ! hciconfig hci0 &>/dev/null; then
    log_error "No Bluetooth adapter found (hci0).  Is Bluetooth enabled?"
    echo "  Try: sudo hciconfig hci0 up"
    exit 1
fi

sudo hciconfig hci0 up 2>/dev/null || true

mkdir -p "${OUTPUT_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCAN_FILE="${OUTPUT_DIR}/ble_scan_${TIMESTAMP}.txt"

log_step "Scanning for BLE devices (${SCAN_DURATION}s)..."
echo "# BLE Scan - $(date -Iseconds)" > "${SCAN_FILE}"
echo "# Duration: ${SCAN_DURATION}s" >> "${SCAN_FILE}"
echo "# -----------------------------------------------" >> "${SCAN_FILE}"

{
    echo "scan on"
    sleep "${SCAN_DURATION}"
    echo "scan off"
    sleep 1
    echo "devices"
    sleep 1
    echo "quit"
} | bluetoothctl 2>/dev/null | grep -E "^\[NEW\]|^Device" | sort -u | while read -r line; do
    echo "${line}" >> "${SCAN_FILE}"
done

log_step "Running LE scan for raw advertisements..."
LESCAN_FILE="${OUTPUT_DIR}/ble_lescan_${TIMESTAMP}.txt"
echo "# BLE LE Scan - $(date -Iseconds)" > "${LESCAN_FILE}"
timeout "${SCAN_DURATION}" sudo hcitool lescan 2>/dev/null >> "${LESCAN_FILE}" || true

DEVICE_COUNT=$(grep -c -E "^Device|\[NEW\]" "${SCAN_FILE}" 2>/dev/null || echo "0")
LE_COUNT=$(wc -l < "${LESCAN_FILE}" 2>/dev/null || echo "0")
LE_COUNT=$((LE_COUNT - 1))

log_info "Found ${DEVICE_COUNT} BLE device(s) via bluetoothctl."
log_info "Found ${LE_COUNT} LE advertisement(s) via hcitool."
log_info "Results saved to:"
echo "       ${SCAN_FILE}"
echo "       ${LESCAN_FILE}"
SCRIPT
}

# ── 12. health_check.sh ─────────────────────────────────────────────
generate_health_check() {
    emit_script "health_check.sh" << 'SCRIPT'
#!/bin/bash
# System health monitor for headless Bjorn deployments.
# Checks CPU temp, memory, disk, network, GPS lock, and Bjorn service status.
set -euo pipefail

BJORN_HOME="/home/bjorn/bjorn"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

OK="${GREEN}OK${NC}"
WARN="${YELLOW}WARN${NC}"
CRIT="${RED}CRIT${NC}"

echo ""
echo "=============================================="
echo "  Bjorn 3B+ System Health Report"
echo "  $(date -Iseconds)"
echo "=============================================="
echo ""

if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP_RAW / 1000))
    TEMP_FRAC=$(( (TEMP_RAW % 1000) / 100 ))
    if [[ ${TEMP_C} -ge 80 ]]; then STATUS="${CRIT}"
    elif [[ ${TEMP_C} -ge 70 ]]; then STATUS="${WARN}"
    else STATUS="${OK}"; fi
    echo -e "  CPU Temperature:  ${TEMP_C}.${TEMP_FRAC} C  [${STATUS}]"
else
    echo -e "  CPU Temperature:  N/A"
fi

MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
if [[ ${MEM_PCT} -ge 90 ]]; then STATUS="${CRIT}"
elif [[ ${MEM_PCT} -ge 75 ]]; then STATUS="${WARN}"
else STATUS="${OK}"; fi
echo -e "  Memory Usage:     ${MEM_PCT}%  (${MEM_USED}/${MEM_TOTAL} kB)  [${STATUS}]"

DISK_PCT=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
if [[ ${DISK_PCT} -ge 90 ]]; then STATUS="${CRIT}"
elif [[ ${DISK_PCT} -ge 75 ]]; then STATUS="${WARN}"
else STATUS="${OK}"; fi
echo -e "  Disk Usage (/):   ${DISK_PCT}%  [${STATUS}]"

UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | sed 's/,.*//')
LOAD=$(awk '{print $1, $2, $3}' /proc/loadavg)
echo -e "  Uptime:           ${UPTIME}"
echo -e "  Load Average:     ${LOAD}"

echo ""
echo "  -- Network ---------------------------------"
for iface in wlan0 wlan1 eth0; do
    if ip link show "${iface}" &>/dev/null; then
        STATE=$(ip link show "${iface}" | awk '/state/ {print $9}')
        ADDR=$(ip -4 addr show "${iface}" 2>/dev/null | awk '/inet / {print $2}' || echo "no address")
        echo -e "    ${iface}:  ${STATE}  ${ADDR}"
    fi
done

echo ""
echo "  -- GPS -------------------------------------"
if systemctl is-active --quiet gpsd 2>/dev/null; then
    echo -e "    GPSD Service:   ${GREEN}running${NC}"
    if command -v gpspipe &>/dev/null; then
        FIX_DATA=$(timeout 3 gpspipe -w 2>/dev/null | head -1 || true)
        if [[ -n "${FIX_DATA}" ]]; then
            echo "    Last report:    ${FIX_DATA:0:80}..."
        else
            echo -e "    Fix Status:     ${YELLOW}no data (waiting for satellites?)${NC}"
        fi
    fi
else
    echo -e "    GPSD Service:   ${YELLOW}not running${NC}"
fi

echo ""
echo "  -- Bjorn -----------------------------------"
if systemctl is-active --quiet bjorn 2>/dev/null; then
    echo -e "    Bjorn Service:  ${GREEN}running${NC}"
elif pgrep -f "bjorn" &>/dev/null; then
    echo -e "    Bjorn Process:  ${GREEN}running (manual)${NC}"
else
    echo -e "    Bjorn Service:  ${YELLOW}not running${NC}"
fi

if [[ -d "${BJORN_HOME}/data/output" ]]; then
    LOOT_COUNT=$(find "${BJORN_HOME}/data/output" -type f 2>/dev/null | wc -l)
    echo "    Loot files:     ${LOOT_COUNT}"
fi

echo ""
echo "  -- Bluetooth -------------------------------"
if hciconfig hci0 &>/dev/null 2>&1; then
    BT_STATE=$(hciconfig hci0 | awk '/UP/ {print "UP"} /DOWN/ {print "DOWN"}')
    echo -e "    Adapter (hci0): ${BT_STATE:-unknown}"
else
    echo -e "    Adapter:        ${YELLOW}not detected${NC}"
fi

echo ""
echo "=============================================="
echo ""
SCRIPT
}

# ── Determine which scripts to generate ─────────────────────────────
GENERATOR_MAP=(
    "env:generate_setup_env"
    "hardware:generate_patch_hardware"
    "wifi:generate_build_wifi"
    "touch:generate_fix_touch"
    "gps:generate_setup_gps"
    "crackstation:generate_crackstation_sync"
    "config:generate_config_patch"
    "teardown:generate_teardown"
    "apply_config:generate_apply_config"
    "gps_logger:generate_gps_logger"
    "ble_scanner:generate_ble_scanner"
    "health:generate_health_check"
)

should_generate() {
    local name="$1"
    if [[ -z "${ONLY_FILTER:-}" ]]; then
        return 0
    fi
    IFS=',' read -ra SELECTED <<< "${ONLY_FILTER}"
    for s in "${SELECTED[@]}"; do
        if [[ "${s}" == "${name}" ]]; then
            return 0
        fi
    done
    return 1
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    ONLY_FILTER=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                echo "Bjorn 3B+ Setup v${VERSION}"
                exit 0
                ;;
            --only)
                if [[ -z "${2:-}" ]]; then
                    log_error "--only requires a comma-separated list of script names."
                    usage
                    exit 1
                fi
                ONLY_FILTER="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    echo ""
    echo "=============================================="
    echo "  Bjorn 3B+ Custom Stack - Script Generator"
    echo "  v${VERSION}"
    echo "=============================================="
    echo ""

    preflight

    mkdir -p "${OUTPUT_DIR}"

    local generated=0
    for entry in "${GENERATOR_MAP[@]}"; do
        local name="${entry%%:*}"
        local func="${entry##*:}"
        if should_generate "${name}"; then
            ${func}
            generated=$((generated + 1))
        fi
    done

    echo ""
    log_info "${generated} script(s) generated in ${OUTPUT_DIR}/"
    echo ""
    echo "  Recommended run order (with sudo where needed):"
    echo "    1.  sudo ./setup_env.sh          # core deps + web assets"
    echo "    2.  sudo ./patch_hardware.sh     # EPD / display bypass"
    echo "    3.  sudo ./build_wifi.sh         # RTL8852BU driver       (optional)"
    echo "    4.       ./fix_touch.sh          # touchscreen rotation   (optional)"
    echo "    5.  sudo ./setup_gps.sh          # GPS receiver setup     (optional)"
    echo "    6.       ./crackstation_sync.py  # hash-lookup utility    (optional)"
    echo "    7.  sudo ./apply_config.sh       # apply config overrides (optional)"
    echo "    8.       ./gps_logger.py         # GPS coordinate logger  (optional)"
    echo "    9.  sudo ./ble_scanner.sh        # BLE device scanner     (optional)"
    echo "   10.       ./health_check.sh       # system health monitor  (optional)"
    echo "   11. sudo ./teardown.sh            # uninstall / rollback   (optional)"
    echo ""
}

main "$@"
