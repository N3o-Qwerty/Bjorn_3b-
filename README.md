# Bjorn 3B+

A custom [Bjorn](https://github.com/infinition/Bjorn) deployment tailored to the **Raspberry Pi 3B+**, adding GPS functionality and an optional hash-lookup utility.

## What's Included

| Script | Purpose |
|---|---|
| `setup_env.sh` | Installs core dependencies (nmap, Python packages) and symlinks the web-UI image assets. |
| `patch_hardware.sh` | Replaces the e-paper display driver with a no-op stub so Bjorn runs in headless / LCD mode. |
| `build_wifi.sh` | Compiles and installs the [RTL8852BU](https://github.com/morrownr/rtl8852bu) USB WiFi driver. |
| `fix_touch.sh` | Rotates the ADS7846 resistive touchscreen 180 degrees (auto-detects the device ID). |
| `setup_gps.sh` | Configures GPSD for U-Blox 7 GPS receivers. |
| `crackstation_sync.py` | Walks the Bjorn loot directory for MD5 hashes and looks them up via a public API. |
| `config_patch.json` | Bjorn configuration overrides (sets `epd_type` to `none`, network interface to `wlan1`). |

## Prerequisites

- Raspberry Pi 3B+ running **Raspberry Pi OS** (Bookworm or later recommended)
- An existing [Bjorn](https://github.com/infinition/Bjorn) installation at `/home/bjorn/bjorn`
- Bash 4+
- Internet connection (for package installs and optional hash lookups)

### Optional hardware

- RTL8852BU USB WiFi adapter (for `build_wifi.sh`)
- ADS7846 resistive touchscreen (for `fix_touch.sh`)
- U-Blox 7 GPS receiver (for `setup_gps.sh`)

## Quick Start

```bash
# 1. Clone this repo onto the Pi
git clone https://github.com/N3o-Qwerty/Bjorn_3b-.git
cd Bjorn_3b-

# 2. Generate the helper scripts
chmod +x Setup.sh
./Setup.sh

# 3. Run the scripts you need (from the output directory)
cd custom_bjorn_scripts/
sudo ./setup_env.sh          # core deps + web assets
sudo ./patch_hardware.sh     # EPD / display bypass
# sudo ./build_wifi.sh       # RTL8852BU driver       (optional)
# ./fix_touch.sh             # touchscreen rotation   (optional)
# sudo ./setup_gps.sh        # GPS receiver setup     (optional)
# ./crackstation_sync.py     # hash-lookup utility    (optional)
```

## Hash-Lookup Utility

`crackstation_sync.py` supports CLI arguments for flexible usage:

```bash
# Default: scan /home/bjorn/bjorn/data/output
./crackstation_sync.py

# Custom loot directory
./crackstation_sync.py --loot-dir /path/to/loot

# Dry run: list discovered hashes without querying the API
./crackstation_sync.py --dry-run
```

## GPS Verification

After running `setup_gps.sh`, verify satellite lock with:

```bash
cgps -s
```

## License

This project is provided as-is for educational and personal use.
