# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] - 2024-12-01

### Added
- `--help` and `--version` flags for `Setup.sh`.
- `--only` flag for selective script generation (e.g. `--only env,gps,health`).
- Write validation in `emit_script()` -- exits with error if a generated file
  is empty or missing.
- **teardown.sh** -- interactive uninstall / rollback script that reverses all
  setup changes.
- **apply_config.sh** -- merges `config_patch.json` into Bjorn's
  `shared_data.json` with automatic backup.
- **gps_logger.py** -- logs GPS coordinates to CSV with configurable interval
  and duration.
- **ble_scanner.sh** -- scans for nearby Bluetooth Low Energy devices and logs
  results.
- **health_check.sh** -- system health monitor (CPU temp, memory, disk,
  network, GPS, Bjorn service status).
- SHA1 and SHA256 hash support in `crackstation_sync.py` (previously MD5 only).
- `--hash-types` argument for `crackstation_sync.py`.
- LICENSE (MIT).
- CONTRIBUTING.md.
- GitHub Actions CI workflow with ShellCheck linting.
- `.editorconfig` for consistent formatting.
- GitHub Issue templates (bug report & feature request).

## [1.0.0] - 2024-11-01

### Added
- Initial release of the Bjorn 3B+ custom stack.
- **setup_env.sh** -- installs core dependencies and links web-UI assets.
- **patch_hardware.sh** -- EPD / display bypass for headless LCD mode.
- **build_wifi.sh** -- RTL8852BU USB WiFi driver compilation.
- **fix_touch.sh** -- ADS7846 touchscreen 180-degree rotation.
- **setup_gps.sh** -- GPSD configuration for U-Blox 7 GPS receivers.
- **crackstation_sync.py** -- MD5 hash-lookup utility.
- **config_patch.json** -- default configuration overrides.
