#!/bin/bash

# --- Configurable parameters ---
PBKDF="pbkdf2"          # PBKDF algorithm to use (default: pbkdf2)
HASH="sha512"           # Hash algorithm to use (default: sha512)
ITERATIONS="100000"     # Number of PBKDF iterations (default: 100000)
KEYSLOT=                # LUKS keyslot to convert (default: auto-detect)
BACKUP_DIR="."          # Directory to store header backups (default: current directory)
AUTO_CONFIRM=false      # Skip confirmation prompts when converting multiple devices
LIST=false              # Discover and analyze current LUKS key setup and devices
DRY_RUN=false           # Perform a dry run without making any changes
LOG_FILE="conversion.log" # Log file to record actions and errors

# --- Command-line argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
  -p | --pbkdf)
    PBKDF="$2"
    shift 2
    ;;
  -hs | --hash)
    HASH="$2"
    shift 2
    ;;
  -i | --iterations)
    ITERATIONS="$2"
    shift 2
    ;;
  -k | --keyslot)
    KEYSLOT="$2"
    shift 2
    ;;
  -d | --device)
    DEVICES+=("$2")
    shift 2
    ;;
  --backup-dir)
    BACKUP_DIR="$2"
    shift 2
    ;;
  --auto-confirm)
    AUTO_CONFIRM=true
    shift
    ;;
  --list)
    LIST=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --log-file)
    LOG_FILE="$2"
    shift 2
    ;;
  -h | --help)
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -p, --pbkdf <pbkdf>          PBKDF algorithm (e.g. pbkdf2, argon2) [default: pbkdf2]"
    echo "  -hs, --hash <hash>           Hash algorithm (e.g. sha512) [default: sha512]"
    echo "  -i, --iterations <iterations> PBKDF iteration count [default: 100000]"
    echo "  -k, --keyslot <keyslot>      LUKS keyslot to convert (0-7) [default: auto-detect]"
    echo "  -d, --device <device>        Path(s) to one or more LUKS devices (can be specified multiple times)"
    echo "  --backup-dir <dir>           Directory to store header backups [default: current directory]"
    echo "  --auto-confirm               Skip confirmation prompts when converting multiple devices"
    echo "  --list                       Discover and analyze current LUKS key setup and devices"
    echo "  --dry-run                    Perform a dry run without making any changes"
    echo "  --log-file <file>            Log file to record actions and errors [default: conversion.log]"
    echo "  -h, --help                   Show this help message and exit"
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

# Function to log messages
log_message() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Ensure backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
  log_message "Backup directory $BACKUP_DIR does not exist."
  exit 1
fi

# Function to check if a command exists
check_command() {
  command -v "$1" >/dev/null 2>&1
}

# Check for required commands
for cmd in cryptsetup blkid lsblk awk; do
  if ! check_command "$cmd"; then
    log_message "Error: Required command '$cmd' not found."
    exit 1
  fi
done

# Function to get the current keyslot
get_current_keyslot() {
  local device="$1"
  cryptsetup luksDump "$device" | awk '$1 ~ /^[0-9]+:$/ && ($2 == "luks1" || $2 == "luks2") {sub(/:$/, "", $1); print $1; exit}'
}

# Device discovery using blkid
discover_devices() {
  if [[ ${#DEVICES[@]} -eq 0 ]]; then
    output=$(blkid | grep 'crypto_LUKS' | cut -d ':' -f 1)
    if [[ -n "$output" ]]; then
      while IFS= read -r device; do
        echo "$device"
        DEVICES+=("$device")
      done <<< "$output"
    else
      log_message "No LUKS devices found using blkid."
      exit 1
    fi
  fi
}

# Discover LUKS setup
list_luks_setup() {
  for DEVICE in "${DEVICES[@]}"; do
    KEYSLOT=$(get_current_keyslot "$DEVICE")
    if [[ -n "$KEYSLOT" ]]; then
      log_message "Device: $DEVICE, Keyslot: $KEYSLOT, PBKDF: argon2, Hash: sha512"
    else
      log_message "Device: $DEVICE, Error: Failed to get current keyslot"
    fi
  done
  exit 0
}

# Auto-detect keyslot if not specified
auto_detect_keyslot() {
  if [[ -z "$KEYSLOT" ]]; then
    KEYSLOT=$(get_current_keyslot "${DEVICES[0]}")
    if [[ -z "$KEYSLOT" ]]; then
      log_message "Failed to auto-detect keyslot. Please specify it manually using -k option."
      exit 1
    fi
    log_message "Auto-detected keyslot: $KEYSLOT"
  fi
}

# Function to generate a temporary name
generate_temp_name() {
  local chars=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789
  local temp_name=""
  for i in {1..12}; do
    temp_name+="${chars:RANDOM%${#chars}:1}"
  done
  echo "luks_$temp_name"
}

# Main conversion loop
convert_keys() {
  for DEVICE in "${DEVICES[@]}"; do
    log_message "Starting conversion for $DEVICE"
    echo "Partitions on $DEVICE:"
    lsblk -P -o NAME,FSTYPE,SIZE,MOUNTPOINT "$DEVICE"  # List partitions on the device

    # Confirm with the user before proceeding, unless AUTO_CONFIRM is true
    if [[ "$AUTO_CONFIRM" != true ]]; then
      read -p "Proceed with key conversion on $DEVICE? [y/N] " confirmed
      if [[ "$confirmed" != "y" && "$confirmed" != "Y" ]]; then
        log_message "Operation aborted by user for $DEVICE."
        continue
      fi
    fi

    # Prompt the user to enter and verify the new password for encryption
    read -sp "Enter the new password for encryption: " password
    echo
    read -sp "Re-enter the new password for verification: " password_verify
    echo

    # Check if the passwords match
    if [[ "$password" != "$password_verify" ]]; then
      log_message "Passwords do not match for $DEVICE. Aborting operation."
      exit 1
    fi

    # Generate a temporary name for the LUKS device mapping
    TEMP_NAME=$(generate_temp_name)
    
    # Open the LUKS device
    if cryptsetup luksOpen "$DEVICE" "$TEMP_NAME"; then
      # Backup the LUKS header
      backup_file="$BACKUP_DIR/$(basename "$DEVICE")_header_backup.bin"
      if ! cryptsetup luksHeaderBackup "/dev/mapper/$TEMP_NAME" --header-backup-file "$backup_file"; then
        log_message "Failed to backup header for $DEVICE. Aborting operation."
        cryptsetup luksClose "$TEMP_NAME" || true
        exit 1
      fi

      # Convert the keyslot with the new password
      if [[ "$DRY_RUN" == true ]]; then
        log_message "Dry run: Would convert keyslot for $DEVICE"
      else
        echo -n "$password" | cryptsetup luksConvertKey "$DEVICE" --key-slot "$KEYSLOT" --pbkdf "$PBKDF" --hash "$HASH" --pbkdf-force-iterations "$ITERATIONS" --key-file -
        cryptsetup luksClose "$TEMP_NAME" || true # Close after convert
      fi

      # Re-open the LUKS device to verify the conversion
      TEMP_NAME=$(generate_temp_name)
      if cryptsetup luksOpen "$DEVICE" "$TEMP_NAME"; then # Verification
        cryptsetup luksClose "$TEMP_NAME" || true
        log_message "Key for $DEVICE (slot $KEYSLOT) converted successfully."
      else
        log_message "ERROR: Failed to open $DEVICE after key conversion. Attempting revert..."
        # Attempt to revert the key conversion if verification fails
        if [[ "$DRY_RUN" == true ]]; then
          log_message "Dry run: Would revert key conversion for $DEVICE"
        else
          if ! cryptsetup luksConvertKey --revert --key-slot "$KEYSLOT" "$DEVICE"; then
            log_message "Reverting key conversion failed for $DEVICE. Manual intervention required."
            cryptsetup luksClose "$TEMP_NAME" || true
            exit 1
          else
            log_message "Key conversion reverted for $DEVICE."
          fi
        fi
        cryptsetup luksClose "$TEMP_NAME" || true
        exit 1 # Exit after revert attempt (even if successful)
      fi

    else
      log_message "Failed to open $DEVICE. Aborting operation."
      exit 1
    fi
    trap "cryptsetup luksClose \"$TEMP_NAME\" || true; exit 1" EXIT # Ensure the LUKS device is closed on exit
  done
}

# Main script execution
discover_devices

if [[ "$LIST" == true ]]; then
  list_luks_setup
fi

auto_detect_keyslot
convert_keys

log_message "Key conversion process completed."

