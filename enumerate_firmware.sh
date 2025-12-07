#!/bin/bash
# Enumerate Sena firmware files from firmware.sena.com
# Pattern: https://firmware.sena.com/senabluetoothmanager/Sena_{DEVICE}-v{VERSION}-build{BUILD}.img
#
# Usage:
#   ./enumerate_firmware.sh             - Enumerate and download firmware files
#   ./enumerate_firmware.sh --dry-run   - Enumerate URLs only (no downloads)
#   ./enumerate_firmware.sh --firmware  - Download and parse official firmware list

# Parse arguments
DRY_RUN=false
FIRMWARE_MODE=false
if [[ "$*" == *"--dry-run"* ]]; then
    DRY_RUN=true
fi
if [[ "$*" == *"--firmware"* ]]; then
    FIRMWARE_MODE=true
fi

# Configuration
MAX_CONCURRENT=100  # Number of concurrent requests
BASE_URL="https://firmware.sena.com/senabluetoothmanager/"
OUTPUT_FILE="firmware_urls.txt"
PARSED_FILE="parsed_urls.txt"
FIRMWARE_DIR="./firmware"
FIRMWARE_LIST_URL="https://firmware.sena.com/senabluetoothmanager/Firmware"

# Languages to exclude (keep only English and lines without language names)
EXCLUDE_LANGUAGES=("French" "Spanish" "Italian" "German" "Korean" "Japanese" "Dutch" "Russian" "Chinese" "Finnish")

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
    local device=$2
    local version=$3
    local build=$4

    # The template filename shows us the pattern to use
    # We need to replace the version and build in the template with our target version/build

    # Strategy: Extract the pattern from the template and apply it to new version/build
    local result=""

    # Common patterns:
    # Sena_{device}-v{version}-build{N}.img
    # Sena_{device}_v{version}-build{N}.img
    # {device}-v{version}-build{N}.img
    # {device}-v{version}.img

    # Determine if template has "Sena_" prefix
    if [[ "$template_filename" == Sena_* ]]; then
        # Check if it uses underscore or dash after device name
        if [[ "$template_filename" =~ Sena_[^-]+_ ]]; then
            # Pattern: Sena_{device}_v{version}...
            if [ -z "$build" ]; then
                result="Sena_${device}_${version}.img"
            else
                result="Sena_${device}_${version}-${build}.img"
            fi
        else
            # Pattern: Sena_{device}-v{version}...
            if [ -z "$build" ]; then
                result="Sena_${device}-${version}.img"
            else
                result="Sena_${device}-${version}-${build}.img"
            fi
        fi
    else
        # No Sena_ prefix - use device name directly
        if [ -z "$build" ]; then
            result="${device}-${version}.img"
        else
            result="${device}-${version}-${build}.img"
        fi
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
    echo "0" > "$COUNTER_FILE"
    echo "0" > "$FOUND_FILE"

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
                ) &

            done
        done <<< "$versions"

    done < "$temp_sorted"

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

# Build numbers (no build suffix, then build0 to build3)
BUILDS=()
# First, try without any build suffix
BUILDS+=("")
# Then try with build numbers
for i in {0..3}; do
    BUILDS+=("build${i}")
done

# If --firmware mode is enabled, process firmware list and exit
if [ "$FIRMWARE_MODE" = true ]; then
    process_firmware_list
    exit 0
fi

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
