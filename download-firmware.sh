#!/bin/bash
# Download Sena firmware files from firmware.sena.com
# Downloads official firmware list and enumerates versions from 1.0.0 to max version
#
# Usage:
#   ./download-firmware.sh             - Enumerate and download firmware files
#   ./download-firmware.sh --dry-run   - Enumerate URLs only (no downloads)

# Parse arguments
DRY_RUN=false
if [[ "$*" == *"--dry-run"* ]]; then
    DRY_RUN=true
fi

# Configuration
MAX_CONCURRENT=1000  # Number of concurrent requests
BASE_URL="https://firmware.sena.com/senabluetoothmanager/"
OUTPUT_FILE="firmware_urls.txt"
PARSED_FILE="parsed_urls.txt"
FIRMWARE_DIR="./firmware"
FIRMWARE_LIST_URL="https://firmware.sena.com/senabluetoothmanager/Firmware"

# Languages to exclude (keep only English and lines without language names)
EXCLUDE_LANGUAGES=("French" "Spanish" "Italian" "German" "Korean" "Japanese" "Dutch" "Russian" "Chinese" "Finnish")

# Function to check if line contains excluded language
contains_excluded_language() {
    local line=$1
    for lang in "${EXCLUDE_LANGUAGES[@]}"; do
        if [[ "$line" == *":$lang:"* ]]; then
            return 0  # Contains excluded language
        fi
    done
    return 1  # Does not contain excluded language
}

# Function to extract version from firmware string
extract_version() {
    local firmware_string=$1
    # Extract the version field (2nd field when split by :)
    local version=$(echo "$firmware_string" | cut -d':' -f2)
    # Remove the 'v' prefix if present
    version=${version#v}
    # Extract major.minor (ignore patch if present)
    local major_minor="${version%.*}"
    if [[ "$version" != *.*.* ]]; then
        # Already in X.Y format
        major_minor="$version"
    fi
    echo "$major_minor"
}

# Function to extract device name from firmware string
extract_device() {
    local firmware_string=$1
    # Extract the device field (1st field when split by :)
    echo "$firmware_string" | cut -d':' -f1
}

# Function to extract filename from firmware string
extract_filename() {
    local firmware_string=$1
    # Extract the filename field (4th field when split by :)
    echo "$firmware_string" | cut -d':' -f4
}

# Function to construct URL from filename template
construct_url_from_template() {
    local template_filename=$1
    local device=$2  # Not used - we extract from template
    local version=$3
    local build=$4

    # Extract the device prefix from the template by removing version and build info
    # Strategy: Find everything before the version pattern

    # Remove .img extension
    local base="${template_filename%.img}"

    # Extract everything before the version (look for -v or _v pattern)
    local device_prefix=""
    if [[ "$base" =~ ^(.+)[-_]v[0-9]+\.[0-9]+ ]]; then
        device_prefix="${BASH_REMATCH[1]}"
    elif [[ "$base" =~ ^(.+)-v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        device_prefix="${BASH_REMATCH[1]}"
    else
        # Fallback: just use the device parameter
        device_prefix="$device"
    fi

    # Determine separator (underscore or dash) between device and version
    local separator="-"
    if [[ "$template_filename" =~ _v[0-9] ]]; then
        separator="_"
    fi

    # Construct new filename
    local result=""
    if [ -z "$build" ]; then
        result="${device_prefix}${separator}${version}.img"
    else
        result="${device_prefix}${separator}${version}-${build}.img"
    fi

    echo "${BASE_URL}${result}"
}

# Function to atomically increment counter
increment_counter() {
    local file=$1
    local lockfile="${file}.lock"

    # Simple file-based locking
    while ! mkdir "$lockfile" 2>/dev/null; do
        sleep 0.01
    done

    local value=$(cat "$file")
    ((value++))
    echo "$value" > "$file"

    rmdir "$lockfile"
    echo "$value"
}

# Function to get counter value
get_counter() {
    cat "$1" 2>/dev/null || echo "0"
}

# Function to download firmware file
download_firmware() {
    local url=$1
    local device=$2

    # Create device-specific directory
    local device_dir="${FIRMWARE_DIR}/${device}"
    mkdir -p "$device_dir"

    # Extract filename from URL
    local filename=$(basename "$url")
    local filepath="${device_dir}/${filename}"

    # Download the file
    if curl -s -o "$filepath" --max-time 60 "$url" 2>/dev/null; then
        echo "  → Downloaded to $filepath"
        return 0
    else
        echo "  ✗ Download failed for $url"
        return 1
    fi
}

# Function to generate version strings from 1.0 to max version
generate_versions() {
    local max_version=$1
    local versions=()

    # Extract major.minor from max_version
    local max_major="${max_version%%.*}"
    local max_rest="${max_version#*.}"
    local max_minor="${max_rest%%.*}"

    # If max_version has patch, extract it
    local max_patch=""
    if [[ "$max_rest" == *.* ]]; then
        max_patch="${max_rest#*.}"
    fi

    # Generate versions from 1.0 to max
    for major in $(seq 1 $max_major); do
        local minor_max=9
        # If we're at max major version, only go up to max minor
        if [ "$major" -eq "$max_major" ]; then
            minor_max=$max_minor
        fi

        for minor in $(seq 0 $minor_max); do
            # Add vX.Y format
            versions+=("v${major}.${minor}")

            # Add vX.Y.Z format
            local patch_max=9
            # If we're at max major.minor, only go up to max patch
            if [ "$major" -eq "$max_major" ] && [ "$minor" -eq "$max_minor" ] && [ -n "$max_patch" ]; then
                patch_max=$max_patch
            fi

            for patch in $(seq 0 $patch_max); do
                versions+=("v${major}.${minor}.${patch}")
            done
        done
    done

    printf '%s\n' "${versions[@]}"
}

# Function to process firmware list from Sena server
process_firmware_list() {
    echo "======================================================================"
    echo "Sena Firmware Enumeration (from Official List)"
    echo "======================================================================"
    echo ""
    echo "Downloading firmware list from $FIRMWARE_LIST_URL"
    echo ""

    # Download the firmware list
    local firmware_list=$(curl -s "$FIRMWARE_LIST_URL")

    if [ -z "$firmware_list" ]; then
        echo "Error: Failed to download firmware list"
        exit 1
    fi

    # Temporary files to store device data
    local temp_devices=$(mktemp)

    # Process each line to extract devices and max versions
    while IFS= read -r line; do
        # Skip empty lines
        [ -z "$line" ] && continue

        # Skip lines that don't end in .img
        [[ ! "$line" =~ \.img$ ]] && continue

        # Skip lines with excluded languages
        contains_excluded_language "$line" && continue

        # Extract information
        local device=$(extract_device "$line")
        local version=$(extract_version "$line")
        local filename=$(extract_filename "$line")

        # Skip if we couldn't extract required fields
        [ -z "$device" ] && continue
        [ -z "$version" ] && continue
        [ -z "$filename" ] && continue

        # Output: device|version|filename
        echo "$device|$version|$filename" >> "$temp_devices"
    done <<< "$firmware_list"

    # Sort and group by device, keeping only the highest version
    local temp_sorted=$(mktemp)
    sort -t'|' -k1,1 -k2,2V "$temp_devices" | \
    awk -F'|' '{
        device=$1
        version=$2
        filename=$3
        # Keep only the latest version for each device
        if (device != prev_device) {
            if (prev_device != "") {
                print prev_device "|" prev_version "|" prev_filename
            }
            prev_device = device
            prev_version = version
            prev_filename = filename
        } else {
            # Update to latest version
            prev_version = version
            prev_filename = filename
        }
    }
    END {
        if (prev_device != "") {
            print prev_device "|" prev_version "|" prev_filename
        }
    }' > "$temp_sorted"

    # Count devices
    local device_count=$(wc -l < "$temp_sorted" | tr -d ' ')

    echo "Found $device_count devices with max versions"
    echo ""

    # Write parsed device list to file
    > "$PARSED_FILE"
    echo "# Sena Firmware Device List (Parsed from Official Firmware List)" >> "$PARSED_FILE"
    echo "# Format: DEVICE | MAX_VERSION | LATEST_URL" >> "$PARSED_FILE"
    echo "#" >> "$PARSED_FILE"

    while IFS='|' read -r device version filename; do
        echo "$device|$version|${BASE_URL}${filename}" >> "$PARSED_FILE"
    done < "$temp_sorted"

    echo "Device list saved to $PARSED_FILE"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo "MODE: Dry-run (URLs only)"
    else
        echo "MODE: Download firmware files to $FIRMWARE_DIR"
    fi
    echo "Using $MAX_CONCURRENT concurrent requests"
    echo ""

    # Clear output file
    > "$OUTPUT_FILE"

    # Create firmware directory if not in dry-run mode
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$FIRMWARE_DIR"
    fi

    # Counter variables
    local TOTAL=0
    local CHECKED=0
    local FOUND=0

    # Create temp directory for coordination
    local TEMP_DIR=$(mktemp -d)
    local COUNTER_FILE="$TEMP_DIR/counter"
    local FOUND_FILE="$TEMP_DIR/found"
    local DOWNLOAD_PIDS_FILE="$TEMP_DIR/download_pids"
    local DEVICE_FOUND_FILE="$TEMP_DIR/device_found"
    echo "0" > "$COUNTER_FILE"
    echo "0" > "$FOUND_FILE"
    touch "$DOWNLOAD_PIDS_FILE"
    touch "$DEVICE_FOUND_FILE"

    # Setup cleanup trap to kill all background jobs on exit/interrupt
    cleanup_on_interrupt() {
        echo ""
        echo "Interrupted! Cleaning up background processes..."

        # Kill all URL checking jobs spawned by this script
        jobs -p | xargs -r kill 2>/dev/null || true

        # Kill all download processes
        if [ -f "$DOWNLOAD_PIDS_FILE" ]; then
            cat "$DOWNLOAD_PIDS_FILE" | xargs -r kill 2>/dev/null || true
        fi

        # Clean up temp files
        rm -rf "$TEMP_DIR"
        exit 1
    }
    trap cleanup_on_interrupt SIGINT SIGTERM

    # Calculate total combinations
    while IFS='|' read -r device max_version filename; do
        local versions=$(generate_versions "$max_version")
        local version_count=$(echo "$versions" | wc -l | tr -d ' ')
        TOTAL=$((TOTAL + version_count * ${#BUILDS[@]}))
    done < "$temp_sorted"

    echo "Testing $TOTAL combinations across $device_count devices"
    echo ""

    # Process each device
    while IFS='|' read -r device max_version example_filename; do
        # Generate all versions for this device
        local versions=$(generate_versions "$max_version")

        # Test each version
        while IFS= read -r version; do
            for build in "${BUILDS[@]}"; do
                # Wait if we've reached max concurrent jobs
                while [ $(jobs -r | wc -l) -ge $MAX_CONCURRENT ]; do
                    sleep 0.1
                done

                # Launch worker in background
                (
                    local checked=$(increment_counter "$COUNTER_FILE")

                    # Construct URL using the template from the example filename
                    local url=$(construct_url_from_template "$example_filename" "$device" "$version" "$build")

                    if [ -z "$build" ]; then
                        local display="${device}-${version}"
                    else
                        local display="${device}-${version}-${build}"
                    fi

                    # Test the URL
                    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --head --max-time 10 "$url" 2>/dev/null)

                    local found=$(get_counter "$FOUND_FILE")

                    if [ "$HTTP_CODE" = "200" ]; then
                        # Increment found counter
                        found=$(increment_counter "$FOUND_FILE")

                        # Mark this device as having found firmware
                        echo "$device" >> "$DEVICE_FOUND_FILE"

                        # Clear the testing line and show found result
                        printf "\r\033[K"
                        echo "✓ FOUND [$checked/$TOTAL]: $url (Total found: $found)"
                        echo "$url" >> "$OUTPUT_FILE"

                        # Download the firmware if not in dry-run mode
                        # Spawn as separate background process (not limited by concurrency)
                        if [ "$DRY_RUN" = false ]; then
                            (
                                download_firmware "$url" "$device"
                            ) &
                            # Track the download PID for cleanup
                            echo $! >> "$DOWNLOAD_PIDS_FILE"
                        fi
                    else
                        # Show current combination being tested
                        printf "\rTesting [$checked/$TOTAL]: %s (Found: %d)... " "$display" "$found"
                    fi
                ) &

            done
        done <<< "$versions"

    done < "$temp_sorted"

    # Wait for all URL checking jobs to complete
    wait

    # Clear the testing line at the end
    printf "\r\033[K"

    # Wait for all downloads to complete if not in dry-run mode
    if [ "$DRY_RUN" = false ]; then
        local download_count=$(wc -l < "$DOWNLOAD_PIDS_FILE" | tr -d ' ')
        if [ "$download_count" -gt 0 ]; then
            echo "Waiting for $download_count downloads to complete..."
            # Wait for all download PIDs
            cat "$DOWNLOAD_PIDS_FILE" | xargs -r -I{} sh -c 'wait {} 2>/dev/null || true'
            echo "All downloads completed."
        fi
    fi

    # Get final counts
    CHECKED=$(get_counter "$COUNTER_FILE")
    FOUND=$(get_counter "$FOUND_FILE")

    # Identify devices with no firmware found
    echo "" >> "$OUTPUT_FILE"
    echo "# Devices with no firmware found:" >> "$OUTPUT_FILE"

    local no_firmware_count=0
    while IFS='|' read -r device max_version filename; do
        # Check if this device had any firmware found
        if ! grep -q "^${device}$" "$DEVICE_FOUND_FILE" 2>/dev/null; then
            echo "# $device (max version: $max_version)" >> "$OUTPUT_FILE"
            echo "⚠ No firmware found for: $device (expected max version: $max_version)"
            ((no_firmware_count++))
        fi
    done < "$temp_sorted"

    echo ""
    echo "======================================================================"
    echo "Enumeration Complete: Found $FOUND firmware files"
    echo "Devices with no firmware: $no_firmware_count"
    echo "======================================================================"
    echo ""

    if [ $FOUND -gt 0 ]; then
        echo "Valid URLs saved to $OUTPUT_FILE"

        if [ "$DRY_RUN" = false ]; then
            echo "Firmware files downloaded to $FIRMWARE_DIR/"
            echo ""
            echo "Downloaded files by device:"
            # List devices that have downloaded files
            for dir in "$FIRMWARE_DIR"/*; do
                if [ -d "$dir" ]; then
                    device=$(basename "$dir")
                    count=$(ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' ')
                    if [ "$count" -gt 0 ]; then
                        echo "  $device: $count files"
                    fi
                fi
            done
        fi

        echo ""
        echo "Summary:"
        cat "$OUTPUT_FILE" | sort
    else
        echo "No firmware files found."
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    rm -f "$temp_devices" "$temp_sorted"
}

# Build numbers (no build suffix, then build0 to build3)
BUILDS=()
# First, try without any build suffix
BUILDS+=("")
# Then try with build numbers
for i in {0..3}; do
    BUILDS+=("build${i}")
done

# Run firmware list processing
process_firmware_list
exit 0
