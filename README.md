# LUKS2 FIPS Fix Script

## Risk Warning

This is currently a work in progress. The script is functional, but it is still being tested and refined. Please use with caution and report any issues you encounter.

There are still areas where the script could be improved, such as error handling, logging, and user interaction. Feedback and suggestions are welcome.

This is provided without warranty or support. Use at your own risk.

## Overview

This script helps to convert LUKS2 keyslots to be FIPS compliant. It is particularly useful for users who did not know they could pass `fips=1` to the anaconda installer at boot to enable FIPS mode during installation. This script allows them to fix their encrypted volumes after the fact, enabling them to comply with FIPS requirements.

If you in this situation and you can just reinstall the system, it is recommended to reinstall the system with FIPS mode enabled from the start. 

This script is intended for users who have already installed the system without FIPS mode and need to convert their encrypted volumes to be FIPS compliant.

## Usage

```bash
./fix-luks2-for-fips.sh [options]
```

## Options

- `-p, --pbkdf <pbkdf>`: PBKDF algorithm (e.g. pbkdf2, argon2) [default: pbkdf2]
- `-hs, --hash <hash>`: Hash algorithm (e.g. sha512) [default: sha512]
- `-i, --iterations <iterations>`: PBKDF iteration count [default: 100000]
- `-k, --keyslot <keyslot>`: LUKS keyslot to convert (0-7) [default: auto-detect]
- `-d, --device <device>`: Path(s) to one or more LUKS devices (can be specified multiple times)
- `--backup-dir <dir>`: Directory to store header backups [default: current directory]
- `--auto-confirm`: Skip confirmation prompts when converting multiple devices
- `--list`: Discover and analyze current LUKS key setup and devices
- `--dry-run`: Perform a dry run without making any changes
- `--log-file <file>`: Log file to record actions and errors [default: conversion.log]
- `-h, --help`: Show this help message and exit

## Logging

The script logs actions and errors to a specified log file. By default, the log file is `conversion.log`. You can specify a different log file using the `--log-file` option.

Example:

```bash
./fix-luks2-for-fips.sh --log-file my_log_file.log
```

The log file will contain timestamps and messages for each action performed by the script.

## Background

When installing a system with FIPS mode enabled, it is necessary to pass the `fips=1` parameter to the anaconda installer at boot. This ensures that the system is configured to comply with FIPS requirements from the start. However, if this step is missed, the encrypted volumes created during installation may not be FIPS compliant.

This script provides a solution for users who find themselves in this situation. It allows them to convert their existing LUKS2 keyslots to be FIPS compliant, enabling them to enable FIPS mode on their system after installation.

## How It Works

The script performs the following steps:

1. Discovers LUKS devices on the system.
2. Backs up the LUKS header for each device.
3. Converts the keyslot to use a FIPS-compliant PBKDF and hash algorithm.
4. Verifies the conversion and logs the results.

By following these steps, the script ensures that the encrypted volumes are compliant with FIPS requirements, allowing the user to enable FIPS mode on their system.
