#!/bin/bash

MONITOR_DIR="/RealRad"
DICOM_DIR="/RealRad/DICOM"
EXECUTE_SCRIPT="/RealRad/.hl7_pdf_dcm.py"
LOG_FILE="/RealRad/ReportsMonitor.log"
IMPORTS_DIR="/imports"
PRELIM_DIR="/PrelimSR"
PRELIM_DICOM_DIR="/PrelimSR/DICOM"

log_message() {
    local LOG_LEVEL="$1"
    local MESSAGE="$2"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$LOG_LEVEL] $MESSAGE" >> "$LOG_FILE"
}

log_message "BASH_INFO" "Starting monitor script."
log_message "BASH_INFO" "Current directory: $(pwd)"
env >> "$LOG_FILE"

mkdir -p "$IMPORTS_DIR"
mkdir -p "$PRELIM_DIR"
mkdir -p "$DICOM_DIR/Processed"
mkdir -p "$DICOM_DIR/Failed"
mkdir -p "$PRELIM_DICOM_DIR/Processed"
mkdir -p "$PRELIM_DICOM_DIR/Failed"

########################################
# Monitor HL7 and FAX files in /RealRad
########################################
inotifywait -m -e create -e moved_to --format "%w%f" "$MONITOR_DIR" | while read -r NEW_FILE; do
    log_message "RUN SCRIPT" " ------- - ------- - ------- "
    log_message "BASH_INFO" "New file detected: $NEW_FILE"

    BASENAME="$(basename "$NEW_FILE")"

    # Skip temp or editor files
    if [[ "$BASENAME" == *.swp || "$BASENAME" == *.tmp || "$BASENAME" == *.swx || "$BASENAME" == *~ ]]; then
        log_message "BASH_INFO" "Ignoring temp file: $BASENAME"
        continue
    fi

    # Handle FAX_*.json files
    if [[ "$BASENAME" == FAX_*.json ]]; then
        log_message "FAX_IMPORT" "FAX file detected: $BASENAME"
        if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
            mv "$NEW_FILE" "$IMPORTS_DIR/"
            log_message "FAX_IMPORT" "Moved FAX file to /imports: $BASENAME"
            /usr/bin/python3.10 -u "$IMPORTS_DIR/.pdfmeV2.1.4.py" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        else
            log_message "FAX_IMPORT_ERR" "FAX file not readable or does not exist: $NEW_FILE"
        fi
        continue
    fi

    # Handle PRELIM_* files
    if [[ "$BASENAME" == PRELIM_* ]]; then
        log_message "PRELIM_SR" "PRELIM file detected: $BASENAME"
        if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
            mv -v "$NEW_FILE" "$PRELIM_DIR/"
            MOVED_FILE="$PRELIM_DIR/$BASENAME"
            log_message "PRELIM_SR" "Moved PRELIM file to /PrelimSR: $BASENAME"
            /usr/bin/python3.10 -u "$PRELIM_DIR/.prelimSR.py" "$MOVED_FILE" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
        else
            log_message "PRELIM_SR_ERR" "PRELIM file not readable or does not exist: $NEW_FILE"
        fi
        continue
    fi

    # Default HL7 file processing (for any readable, non-FAX file)
    if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
        cd "$MONITOR_DIR" || { log_message "BASH_ERR" "Failed to change directory to $MONITOR_DIR"; exit 1; }
        log_message "BASH_INFO" "Executing Python script: $EXECUTE_SCRIPT"
        /usr/bin/python3.10 -u "$EXECUTE_SCRIPT" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
    else
        log_message "BASH_ERR" "File not readable or does not exist: $NEW_FILE"
    fi
done &

###########################################
# Monitor DICOM files in /RealRad/DICOM
###########################################
inotifywait -m -e create -e moved_to --format "%w%f" "$DICOM_DIR" | while read -r NEW_DICOM_FILE; do
    log_message "BASH_INFO" "New DICOM file detected: $NEW_DICOM_FILE"

    if [[ -f "$NEW_DICOM_FILE" && -r "$NEW_DICOM_FILE" ]]; then
        UNCOMPRESSED_FILE="${NEW_DICOM_FILE%.dcm}_uncompressed.dcm"
        dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE"

        if storescu -v -aet CMICCH -aec COMPASS 10.201.100.100 104 "$UNCOMPRESSED_FILE"; then
            log_message "BASH_INFO" "DICOM file sent successfully: $UNCOMPRESSED_FILE"
            rm -f "$UNCOMPRESSED_FILE"
            log_message "BASH_INFO" "Deleted uncompressed file: $UNCOMPRESSED_FILE"
            mv "$NEW_DICOM_FILE" "$DICOM_DIR/Processed/"
            log_message "BASH_INFO" "Original: $NEW_DICOM_FILE moved to $DICOM_DIR/Processed/"
        else
            log_message "BASH_ERR" "Failed to send DICOM file: $UNCOMPRESSED_FILE"
            mv "$UNCOMPRESSED_FILE" "$DICOM_DIR/Failed/"
            log_message "BASH_INFO" "DICOM file moved to Failed directory: $UNCOMPRESSED_FILE"
        fi
    else
        log_message "BASH_ERR" "Detected file does not exist or is not accessible: $NEW_DICOM_FILE"
    fi
done &

##########################################################
# Monitor PRELIM DICOM files in /PrelimSR/DICOM
# AET comes from filename before first "_"
##########################################################
inotifywait -m -e create -e moved_to --format "%w%f" "$PRELIM_DICOM_DIR" | while read -r NEW_DICOM_FILE; do
    log_message "BASH_INFO" "New PRELIM DICOM file detected: $NEW_DICOM_FILE"

    if [[ -f "$NEW_DICOM_FILE" && -r "$NEW_DICOM_FILE" ]]; then
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
        dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE"

        if storescu -v -aet "$AET" -aec NIGHTHAWK_SR 10.201.100.100 104 "$UNCOMPRESSED_FILE"; then
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
        log_message "BASH_ERR" "Detected PRELIM DICOM file does not exist or is not accessible: $NEW_DICOM_FILE"
    fi
done