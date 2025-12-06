#!/bin/bash
# Enumerate Sena firmware files from firmware.sena.com
# Pattern: https://firmware.sena.com/senabluetoothmanager/Sena_{DEVICE}-v{VERSION}-build{BUILD}.img
#
# Usage:
#   ./enumerate_firmware.sh             - Enumerate and download firmware files
#   ./enumerate_firmware.sh --dry-run   - Enumerate URLs only (no downloads)

# Parse arguments
DRY_RUN=false
if [[ "$*" == *"--dry-run"* ]]; then
    DRY_RUN=true
fi

# Configuration
MAX_CONCURRENT=100  # Number of concurrent requests
BASE_URL="https://firmware.sena.com/senabluetoothmanager/"
OUTPUT_FILE="firmware_urls.txt"
FIRMWARE_DIR="./firmware"

# Known Sena device models from web research
DEVICE_MODELS=(
    # 60 Series
#    "60S" "60X"
    # 50 Series
    "50S" "50R" "50C"
    # 30 Series
    "30K"
    # 20 Series
    "20S" "20S-EVO"
    # 10 Series
    "10S" "10R" "10C" "10C-EVO" "10C-PRO"
    # 5 Series
    "5S" "5R" "5R-Lite"
    # SF Series
    "SF1" "SF2" "SF4" "SFR"
    # SMH Series
    "SMH10" "SMH10R" "SMH5" "SMH5-FM"
    # 3 Series
    "3S" "3S-Plus"
    # Spider Series
    "Spider-RT1" "Spider-ST1" "Spider-X-Slim"
    # Other
    "Apex" "Apex-Plus" "Vortex" "Vortex-Hi-Fi"
    "R1" "R1-EVO" "R2" "R2-EVO"
    "M1" "M1-EVO"
)

#DEVICE_MODELS=(
#    "50S"
#)

# Function to get max version for a device (from Sena website research)
get_max_version() {
    local device=$1

    case "$device" in
        "60S") echo "1.1" ;;
        "50S") echo "2.7" ;;
        "50R") echo "2.7" ;;
        "50C") echo "1.2" ;;
        "30K") echo "1.0" ;;
        "20S") echo "1.7" ;;
        "20S-EVO") echo "2.2" ;;
        "10S") echo "2.1" ;;
        "5S") echo "2.2" ;;
        "SF1") echo "3.3" ;;
        "SF2") echo "3.3" ;;
        "SF4") echo "3.4" ;;
        "SMH5") echo "3.0" ;;
        "SMH5-FM") echo "3.0" ;;
        "SMH10") echo "5.1" ;;
        "SMH10R") echo "5.1" ;;
        *) echo "3.9" ;;  # Default for unlisted devices
    esac
}

# Function to check if version is within max for device
version_within_max() {
    local version=$1  # format: vX.Y or vX.Y.Z
    local max=$2      # format: X.Y

    # Strip the 'v' prefix
    version=${version#v}

    # Extract major.minor from version (ignore patch)
    local major_minor="${version%.*}"
    if [[ "$version" != *.*.* ]]; then
        # Already in X.Y format
        major_minor="$version"
    fi

    # Compare versions (simple string comparison works for X.Y format)
    local ver_major="${major_minor%%.*}"
    local ver_minor="${major_minor##*.}"
    local max_major="${max%%.*}"
    local max_minor="${max##*.}"

    # Ensure we have valid integers (default to 0 if empty)
    ver_major=${ver_major:-0}
    ver_minor=${ver_minor:-0}
    max_major=${max_major:-0}
    max_minor=${max_minor:-0}

    if [ "$ver_major" -lt "$max_major" ]; then
        return 0  # within max
    elif [ "$ver_major" -eq "$max_major" ] && [ "$ver_minor" -le "$max_minor" ]; then
        return 0  # within max
    else
        return 1  # exceeds max
    fi
}

# Generate version strings (v1.0 to v3.9 and v1.0.0 to v3.9.9)
VERSIONS=()
for major in {1..3}; do
    for minor in {0..9}; do
        # Add vX.Y format
        VERSIONS+=("v${major}.${minor}")
        # Add vX.Y.Z format
        for patch in {0..9}; do
            VERSIONS+=("v${major}.${minor}.${patch}")
        done
    done
done

# Build numbers (no build suffix, then build0 to build5)
BUILDS=()
# First, try without any build suffix
BUILDS+=("")
# Then try with build numbers
for i in {0..5}; do
    BUILDS+=("build${i}")
done

# Counter variables
TOTAL=0
CHECKED=0
FOUND=0

# Create temp directory for coordination
TEMP_DIR=$(mktemp -d)
COUNTER_FILE="$TEMP_DIR/counter"
FOUND_FILE="$TEMP_DIR/found"
echo "0" > "$COUNTER_FILE"
echo "0" > "$FOUND_FILE"

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

# Calculate total combinations (accounting for max versions per device)
TOTAL=0
for device in "${DEVICE_MODELS[@]}"; do
    max_version=$(get_max_version "$device")
    version_count=0
    for version in "${VERSIONS[@]}"; do
        if version_within_max "$version" "$max_version"; then
            ((version_count++))
        fi
    done
    TOTAL=$((TOTAL + version_count * ${#BUILDS[@]}))
done

echo "======================================================================"
echo "Sena Firmware Enumeration Tool"
echo "======================================================================"
echo ""
if [ "$DRY_RUN" = true ]; then
    echo "MODE: Dry-run (URLs only)"
else
    echo "MODE: Download firmware files to $FIRMWARE_DIR"
fi
echo "Testing $TOTAL combinations across ${#DEVICE_MODELS[@]} devices"
echo "Using device-specific max firmware versions from Sena website"
echo "Using $MAX_CONCURRENT concurrent requests"
echo ""

# Clear output file
> "$OUTPUT_FILE"

# Create firmware directory if not in dry-run mode
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$FIRMWARE_DIR"
fi

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

# Worker function to check a single URL
check_url_worker() {
    local device=$1
    local version=$2
    local build=$3

    # Increment checked counter
    local checked=$(increment_counter "$COUNTER_FILE")

    # Construct URL - only add dash before build if build is not empty
    if [ -z "$build" ]; then
        local url="${BASE_URL}Sena_${device}-${version}.img"
        local display="${device}-${version}"
    else
        local url="${BASE_URL}Sena_${device}-${version}-${build}.img"
        local display="${device}-${version}-${build}"
    fi

    # Use curl HEAD request with timeout
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --head --max-time 10 "$url" 2>/dev/null)

    local found=$(get_counter "$FOUND_FILE")

    if [ "$HTTP_CODE" = "200" ]; then
        # Increment found counter
        found=$(increment_counter "$FOUND_FILE")

        # Clear the testing line and show found result
        printf "\r\033[K"
        echo "✓ FOUND [$checked/$TOTAL]: $url (Total found: $found)"
        echo "$url" >> "$OUTPUT_FILE"

        # Download the firmware if not in dry-run mode
        if [ "$DRY_RUN" = false ]; then
            download_firmware "$url" "$device"
        fi
    else
        # Show current combination being tested
        printf "\rTesting [$checked/$TOTAL]: %s (Found: %d)... " "$display" "$found"
    fi
}

# Main enumeration loop with parallelization
for device in "${DEVICE_MODELS[@]}"; do
    # Get max version for this device
    max_version=$(get_max_version "$device")

    for version in "${VERSIONS[@]}"; do
        # Skip versions that exceed the max for this device
        if ! version_within_max "$version" "$max_version"; then
            continue
        fi

        for build in "${BUILDS[@]}"; do
            # Wait if we've reached max concurrent jobs
            while [ $(jobs -r | wc -l) -ge $MAX_CONCURRENT ]; do
                sleep 0.1
            done

            # Launch worker in background
            check_url_worker "$device" "$version" "$build" &
        done
    done
done

# Wait for all remaining background jobs to complete
wait

# Clear the testing line at the end
printf "\r\033[K"

# Get final counts
CHECKED=$(get_counter "$COUNTER_FILE")
FOUND=$(get_counter "$FOUND_FILE")

echo ""
echo "======================================================================"
echo "Enumeration Complete: Found $FOUND firmware files"
echo "======================================================================"
echo ""

if [ $FOUND -gt 0 ]; then
    echo "Valid URLs saved to $OUTPUT_FILE"

    if [ "$DRY_RUN" = false ]; then
        echo "Firmware files downloaded to $FIRMWARE_DIR/"
        echo ""
        echo "Downloaded files by device:"
        for device in "${DEVICE_MODELS[@]}"; do
            if [ -d "$FIRMWARE_DIR/$device" ]; then
                count=$(ls -1 "$FIRMWARE_DIR/$device" 2>/dev/null | wc -l)
                if [ $count -gt 0 ]; then
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
