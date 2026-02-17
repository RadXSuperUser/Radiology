#!/bin/bash

MONITOR_DIR="/var/lib/filemonitor"
LOG_FILE="/opt/FileMonitor.log"
HL7toDICOM_DIR="/var/lib/filemonitor/HL7toDICOM"
HL7toDICOM_SCRIPT="/opt/hl7toDICOM.py"
FAX_DIR="/var/lib/filemonitor/FAX"
FAX_SCRIPT="/opt/ORU2pdf.py"
PRELIM_DIR="/var/lib/filemonitor/PrelimSR"
PRELIM_DICOM_DIR="/var/lib/filemonitor/PrelimSR/DICOM"

# DICOM send configuration
DICOM_HOST="192.168.1.25"
DICOM_PORT="104"
DICOM_AET="ORTHANC"
DICOM_AEC="SBDEMO"
PRELIM_AEC="NIGHTHAWK_SR"

log_message() {
    local LOG_LEVEL="$1"
    local MESSAGE="$2"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$LOG_LEVEL] $MESSAGE" >> "$LOG_FILE"
}

# Wait for file to be completely written (size stable)
wait_for_file_complete() {
    local file_path="$1"
    local max_wait=30
    local check_interval=0.5
    local last_size=-1
    local stable_count=0
    local required_stable=2
    
    if [ ! -f "$file_path" ]; then
        return 1
    fi
    
    for ((i=0; i<$((max_wait * 2)); i++)); do
        if [ ! -f "$file_path" ]; then
            return 1
        fi
        
        current_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
        if [ -z "$current_size" ]; then
            sleep "$check_interval"
            continue
        fi
        
        if [ "$current_size" -eq "$last_size" ]; then
            ((stable_count++))
            if [ "$stable_count" -ge "$required_stable" ]; then
                return 0
            fi
        else
            stable_count=0
            last_size=$current_size
        fi
        sleep "$check_interval"
    done
    
    # If we get here, file might still be writing, but proceed anyway
    log_message "BASH_WARN" "File size not stable after ${max_wait}s, proceeding: $file_path"
    return 0
}

log_message "BASH_INFO" "Starting monitor script."
log_message "BASH_INFO" "Current directory: $(pwd)"

mkdir -p "$HL7toDICOM_DIR"
mkdir -p "$FAX_DIR"
mkdir -p "$PRELIM_DIR"

########################################
# Monitor files in /var/lib/filemonitor
########################################
inotifywait -m -e close_write -e moved_to --format "%w%f" "$MONITOR_DIR" 2>>"LOG_FILE" | while read -r NEW_FILE; do
    log_message "RUN SCRIPT" " ------- - ------- - ------- "
    log_message "BASH_INFO" "New file detected: $NEW_FILE"

    BASENAME="$(basename "$NEW_FILE")"

    # Skip temp or editor files
    if [[ "$BASENAME" == *.swp || "$BASENAME" == *.tmp || "$BASENAME" == *.swx || "$BASENAME" == *~ ]]; then
        log_message "BASH_INFO" "Ignoring temp file: $BASENAME"
        continue
    fi

    # Skip DICOM directory (handled separately)
    if [[ "$NEW_FILE" == "$HL7toDICOM_DIR"/* ]]; then
        continue
    fi

    # Handle FAX_*.json files
    if [[ "$BASENAME" == FAX_*.json ]]; then
        log_message "FAX_FILE" "FAX file detected: $BASENAME"
        if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
            wait_for_file_complete "$NEW_FILE"
            mv "$NEW_FILE" "$FAX_DIR/"
            log_message "FAX_FILE" "Moved FAX file to $FAX_DIR: $BASENAME"
            /usr/bin/python3.12 -u "$FAX_SCRIPT" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        else
            log_message "FAX_FILE_ERR" "FAX file not readable or does not exist: $NEW_FILE"
        fi
        continue
    fi

    # Handle PRELIM_* files
    if [[ "$BASENAME" == PRELIM_* ]]; then
        log_message "PRELIM_SR" "PRELIM file detected: $BASENAME"
        if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
            wait_for_file_complete "$NEW_FILE"
            mv -v "$NEW_FILE" "$PRELIM_DIR/"
            MOVED_FILE="$PRELIM_DIR/$BASENAME"
            log_message "PRELIM_SR" "Moved PRELIM file to /PrelimSR: $BASENAME"
            /usr/bin/python3.12 -u "$PRELIM_DIR/.prelimSR.py" "$MOVED_FILE" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        else
            log_message "PRELIM_SR_ERR" "PRELIM file not readable or does not exist: $NEW_FILE"
        fi
        continue
    fi

    # Handle PDF-Base64 HL7 files
    if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
        wait_for_file_complete "$NEW_FILE"

        # OPTIMIZED: Pass file path as argument instead of letting Python scan directory
        # This eliminates double monitoring and ensures only the new file is processed
        log_message "BASH_INFO" "Executing Python script with file: $HL7toDICOM_SCRIPT $NEW_FILE"

        # Check if script accepts file argument (optimized version)
        if grep -q "sys.argv" "$HL7toDICOM_SCRIPT" 2>/dev/null; then
            /usr/bin/python3.12 -u "$HL7toDICOM_SCRIPT" "$NEW_FILE" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        else
            # Fallback: old behavior (script scans directory itself)
            cd "$MONITOR_DIR" || { log_message "BASH_ERR" "Failed to change directory to $MONITOR_DIR"; exit 1; }
            /usr/bin/python3.12 -u "$HL7toDICOM_SCRIPT" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        fi
    else
        log_message "BASH_ERR" "File not readable or does not exist: $NEW_FILE"
    fi
done

###########################################
# Monitor DICOM files in /var/lib/filemonitor/HL7toDICOM/DICOM
###########################################
inotifywait -m -e create -e moved_to --format "%w%f" "$HL7toDICOM_DIR" | while read -r NEW_DICOM_FILE; do
    log_message "BASH_INFO" "New DICOM file detected: $NEW_DICOM_FILE"

    if [[ -f "$NEW_DICOM_FILE" && -r "$NEW_DICOM_FILE" ]]; then
        wait_for_file_complete "$NEW_DICOM_FILE"

        UNCOMPRESSED_FILE="${NEW_DICOM_FILE%.dcm}_uncompressed.dcm"

        # OPTIMIZED: Check if dcmdjpeg succeeds before proceeding
        if dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE" 2>> "$LOG_FILE"; then
            log_message "BASH_INFO" "Successfully uncompressed DICOM file: $NEW_DICOM_FILE"

            # Send DICOM file
            if storescu -v -aet "$DICOM_AET" -aec "$DICOM_AEC" "$DICOM_HOST" "$DICOM_PORT" "$UNCOMPRESSED_FILE" 2>> "$LOG_FILE"; then        
                log_message "BASH_INFO" "DICOM file sent successfully: $UNCOMPRESSED_FILE"
                rm -f "$UNCOMPRESSED_FILE"
                log_message "BASH_INFO" "Deleted uncompressed file: $UNCOMPRESSED_FILE"
                mv "$NEW_DICOM_FILE" "$HL7toDICOM_DIR/Processed/"
                log_message "BASH_INFO" "Original: $NEW_DICOM_FILE moved to $HL7toDICOM_DIR/Processed/"
            else
                log_message "BASH_ERR" "Failed to send DICOM file: $UNCOMPRESSED_FILE"
                mv "$UNCOMPRESSED_FILE" "$HL7toDICOM_DIR/Failed/"
                log_message "BASH_INFO" "DICOM file moved to Failed directory: $UNCOMPRESSED_FILE"
            fi
        else
            log_message "BASH_ERR" "Failed to uncompress DICOM file: $NEW_DICOM_FILE"
            mv "$NEW_DICOM_FILE" "$HL7toDICOM_DIR/Failed/"
            log_message "BASH_INFO" "Original DICOM file moved to Failed directory: $NEW_DICOM_FILE"
        fi
    else
        log_message "BASH_ERR" "Detected file does not exist or is not accessible: $NEW_DICOM_FILE"
    fi
done

##########################################################
# Monitor PRELIM DICOM files in /PrelimSR/DICOM
# AET comes from filename before first "_"
##########################################################
inotifywait -m -e create -e moved_to --format "%w%f" "$PRELIM_DICOM_DIR" | while read -r NEW_DICOM_FILE; do
    log_message "BASH_INFO" "New PRELIM DICOM file detected: $NEW_DICOM_FILE"

    if [[ -f "$NEW_DICOM_FILE" && -r "$NEW_DICOM_FILE" ]]; then
        wait_for_file_complete "$NEW_DICOM_FILE"

        BASENAME="$(basename "$NEW_DICOM_FILE")"

        # Guard rail: Require underscore in filename
        if [[ "$BASENAME" != *_* ]]; then
            log_message "PRELIM_DICOM_ERR" "Filename missing required underscore: $BASENAME"
            mv "$NEW_DICOM_FILE" "$PRELIM_DICOM_DIR/Failed/"
            log_message "PRELIM_DICOM_ERR" "Moved invalid DICOM file to Failed: $NEW_DICOM_FILE"
            continue
        fi

        # Extract AET from filename before the first underscore
        # e.g. GIGN_1234565.dcm -> GIGN
        AET="${BASENAME%%_*}"
        AET="${AET%.dcm}"

        UNCOMPRESSED_FILE="${NEW_DICOM_FILE%.dcm}_uncompressed.dcm"

        # OPTIMIZED: Check if dcmdjpeg succeeds before proceeding
        if dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE" 2>> "$LOG_FILE"; then
            log_message "BASH_INFO" "Successfully uncompressed PRELIM DICOM file: $NEW_DICOM_FILE"

            if storescu -v -aet "$AET" -aec "$PRELIM_AEC" "$DICOM_HOST" "$DICOM_PORT" "$UNCOMPRESSED_FILE" 2>> "$LOG_FILE"; then
                log_message "BASH_INFO" "PRELIM DICOM file sent successfully (AET=$AET): $UNCOMPRESSED_FILE"
                rm -f "$UNCOMPRESSED_FILE"
                log_message "BASH_INFO" "Deleted uncompressed PRELIM DICOM file: $UNCOMPRESSED_FILE"
                mv "$NEW_DICOM_FILE" "$PRELIM_DICOM_DIR/Processed/"
                log_message "BASH_INFO" "Original PRELIM DICOM moved to Processed/: $NEW_DICOM_FILE"
            else
                log_message "BASH_ERR" "Failed to send PRELIM DICOM file (AET=$AET): $UNCOMPRESSED_FILE"
                mv "$UNCOMPRESSED_FILE" "$PRELIM_DICOM_DIR/Failed/"
                log_message "BASH_INFO" "PRELIM DICOM file moved to Failed directory: $UNCOMPRESSED_FILE"
            fi
        else
            log_message "BASH_ERR" "Failed to uncompress PRELIM DICOM file: $NEW_DICOM_FILE"
            mv "$NEW_DICOM_FILE" "$PRELIM_DICOM_DIR/Failed/"
            log_message "BASH_INFO" "Original PRELIM DICOM file moved to Failed directory: $NEW_DICOM_FILE"
        fi
    else
        log_message "BASH_ERR" "Detected PRELIM DICOM file does not exist or is not accessible: $NEW_DICOM_FILE"
    fi
done