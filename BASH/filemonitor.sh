#!/bin/bash

MONITOR_DIR="/var/lib/filemonitor"
LOG_FILE="/opt/FileMonitor.log"
HL7toDICOM_DIR="/var/lib/filemonitor/HL7toDICOM/DICOM"
HL7toDICOM_SCRIPT="/opt/hl7toDICOM.py"
FAX_DIR="/var/lib/filemonitor/FAX"
FAX_SCRIPT="/opt/ORU2pdf.py"
PRELIM_DIR="/var/lib/filemonitor/PrelimSR"
PRELIM_SCRIPT="/opt/prelimSR.py"
PRELIM_DICOM_DIR="/var/lib/filemonitor/PrelimSR/DICOM"

# Per-script log files (detailed output stays out of main log)
LOG_DIR_FAX="/var/lib/filemonitor/FAX/logs"
LOG_DIR_PRELIM="/var/lib/filemonitor/PrelimSR/logs"
LOG_DIR_HL7="/var/lib/filemonitor/HL7toDICOM/logs"
LOG_ORU2PDF="${LOG_DIR_FAX}/ORU2pdf.log"
LOG_PRELIMSR="${LOG_DIR_PRELIM}/prelimSR.log"
LOG_HL7DCM="${LOG_DIR_HL7}/hl7_pdf_dcm.log"

# DICOM send configuration
DICOM_HOST="192.168.1.25"
DICOM_PORT="104"
DICOM_AET="ORTHANC"
DICOM_AEC="SBDEMO"
PRELIM_AEC="NIGHTHAWK_SR"

# Main log: one-line entries only (file handling + script outcome)
log_main() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# Wait for file to be completely written (size stable)
wait_for_file_complete() {
    local file_path="$1"
    local max_wait=30
    local check_interval=0.5
    local last_size=-1
    local stable_count=0
    local required_stable=2

    [[ ! -f "$file_path" ]] && return 1

    for ((i=0; i<$((max_wait * 2)); i++)); do
        [[ ! -f "$file_path" ]] && return 1
        current_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)
        [[ -z "$current_size" ]] && { sleep "$check_interval"; continue; }
        if [[ "$current_size" -eq "$last_size" ]]; then
            ((stable_count++))
            [[ "$stable_count" -ge "$required_stable" ]] && return 0
        else
            stable_count=0
            last_size=$current_size
        fi
        sleep "$check_interval"
    done
    log_main "WARN file size not stable after ${max_wait}s, proceeding: $(basename "$file_path")"
    return 0
}

mkdir -p "$HL7toDICOM_DIR" "$FAX_DIR" "$PRELIM_DIR"
mkdir -p "$HL7toDICOM_DIR/Processed" "$HL7toDICOM_DIR/Failed" "$PRELIM_DICOM_DIR/Processed" "$PRELIM_DICOM_DIR/Failed"
mkdir -p "$LOG_DIR_FAX" "$LOG_DIR_PRELIM" "$LOG_DIR_HL7"

log_main "START FileMonitor (main=$MONITOR_DIR, FAX->$FAX_DIR, PRELIM->$PRELIM_DIR, HL7->$HL7toDICOM_DIR)"

########################################
# Monitor 1: files in monitor root only
########################################
monitor_root() {
    inotifywait -m -e close_write -e moved_to --format "%w%f" "$MONITOR_DIR" 2>>"$LOG_FILE" | while read -r NEW_FILE; do
        # Only handle files directly under MONITOR_DIR (ignore events from subdirs)
        if [[ "$NEW_FILE" == "$MONITOR_DIR"/*/* ]]; then
            continue
        fi

        BASENAME="$(basename "$NEW_FILE")"
        if [[ "$BASENAME" == *.swp || "$BASENAME" == *.tmp || "$BASENAME" == *.swx || "$BASENAME" == *~ ]]; then
            continue
        fi
        if [[ "$NEW_FILE" == "$HL7toDICOM_DIR"/* ]]; then
            continue
        fi

        # FAX_*.json -> FAX_DIR, script ORU2pdf.py
        if [[ "$BASENAME" == FAX_*.json ]]; then
            if [[ ! -f "$NEW_FILE" || ! -r "$NEW_FILE" ]]; then
                log_main "ERR FAX file not readable: $BASENAME"
                continue
            fi
            wait_for_file_complete "$NEW_FILE"
            mv "$NEW_FILE" "$FAX_DIR/"
            log_main "RECV FAX $BASENAME -> $FAX_DIR | script ORU2pdf.py"
            if /opt/radx-workflow/bin/python -u "$FAX_SCRIPT" >> "$LOG_ORU2PDF" 2>&1; then
                log_main "DONE ORU2pdf.py $BASENAME ok"
            else
                log_main "DONE ORU2pdf.py $BASENAME err (see $LOG_ORU2PDF)"
            fi
            continue
        fi

        # PRELIM_* -> PRELIM_DIR, script prelimSR.py
        if [[ "$BASENAME" == PRELIM_* ]]; then
            if [[ ! -f "$NEW_FILE" || ! -r "$NEW_FILE" ]]; then
                log_main "ERR PRELIM file not readable: $BASENAME"
                continue
            fi
            wait_for_file_complete "$NEW_FILE"
            mv "$NEW_FILE" "$PRELIM_DIR/"
            MOVED_FILE="$PRELIM_DIR/$BASENAME"
            log_main "RECV PRELIM $BASENAME -> $PRELIM_DIR | script prelimSR.py"
            if /opt/radx-workflow/bin/python -u "$PRELIM_SCRIPT" "$MOVED_FILE" >> "$LOG_PRELIMSR" 2>&1; then
                log_main "DONE prelimSR.py $BASENAME ok"
            else
                log_main "DONE prelimSR.py $BASENAME err (see $LOG_PRELIMSR)"
            fi
            continue
        fi

        # HL7 (PDF-Base64) -> process in place, script hl7_pdf_dcm.py
        if [[ -f "$NEW_FILE" && -r "$NEW_FILE" ]]; then
            wait_for_file_complete "$NEW_FILE"
            log_main "RECV HL7 $(basename "$NEW_FILE") -> $HL7toDICOM_DIR | script hl7_pdf_dcm.py"
            if grep -q "sys.argv" "$HL7toDICOM_SCRIPT" 2>/dev/null; then
                if /opt/radx-workflow/bin/python -u "$HL7toDICOM_SCRIPT" "$NEW_FILE" >> "$LOG_HL7DCM" 2>&1; then
                    log_main "DONE hl7_pdf_dcm.py $(basename "$NEW_FILE") ok"
                else
                    log_main "DONE hl7_pdf_dcm.py $(basename "$NEW_FILE") err (see $LOG_HL7DCM)"
                fi
            else
                if /opt/radx-workflow/bin/python -u "$HL7toDICOM_SCRIPT" >> "$LOG_HL7DCM" 2>&1; then
                    log_main "DONE hl7_pdf_dcm.py ok"
                else
                    log_main "DONE hl7_pdf_dcm.py err (see $LOG_HL7DCM)"
                fi
            fi
        else
            log_main "ERR file not readable: $BASENAME"
        fi
    done
}

###########################################
# Monitor 2: DICOM in HL7toDICOM (send to PACS)
###########################################
monitor_hl7_dicom() {
    inotifywait -m -e create -e moved_to --format "%w%f" "$HL7toDICOM_DIR" 2>/dev/null | while read -r NEW_DICOM_FILE; do
        [[ ! -f "$NEW_DICOM_FILE" || ! -r "$NEW_DICOM_FILE" ]] && continue
        wait_for_file_complete "$NEW_DICOM_FILE"
        BN="$(basename "$NEW_DICOM_FILE")"
        UNCOMPRESSED_FILE="${NEW_DICOM_FILE%.dcm}_uncompressed.dcm"

        if dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE" >> "$LOG_HL7DCM" 2>&1; then
            if storescu -v -aet "$DICOM_AET" -aec "$DICOM_AEC" "$DICOM_HOST" "$DICOM_PORT" "$UNCOMPRESSED_FILE" >> "$LOG_HL7DCM" 2>&1; then
                rm -f "$UNCOMPRESSED_FILE"
                mkdir -p "$HL7toDICOM_DIR/Processed"
                mv "$NEW_DICOM_FILE" "$HL7toDICOM_DIR/Processed/"
                log_main "DICOM HL7 $BN -> Processed/ | sent PACS ok"
            else
                mkdir -p "$HL7toDICOM_DIR/Failed"
                mv "$UNCOMPRESSED_FILE" "$HL7toDICOM_DIR/Failed/"
                log_main "DICOM HL7 $BN -> Failed/ | PACS send err"
            fi
        else
            mkdir -p "$HL7toDICOM_DIR/Failed"
            mv "$NEW_DICOM_FILE" "$HL7toDICOM_DIR/Failed/"
            log_main "DICOM HL7 $BN -> Failed/ | uncompress err"
        fi
    done
}

###########################################
# Monitor 3: PRELIM DICOM in PrelimSR/DICOM (send to PACS)
###########################################
monitor_prelim_dicom() {
    inotifywait -m -e create -e moved_to --format "%w%f" "$PRELIM_DICOM_DIR" 2>/dev/null | while read -r NEW_DICOM_FILE; do
        [[ ! -f "$NEW_DICOM_FILE" || ! -r "$NEW_DICOM_FILE" ]] && continue
        wait_for_file_complete "$NEW_DICOM_FILE"
        BASENAME="$(basename "$NEW_DICOM_FILE")"

        if [[ "$BASENAME" != *_* ]]; then
            mkdir -p "$PRELIM_DICOM_DIR/Failed"
            mv "$NEW_DICOM_FILE" "$PRELIM_DICOM_DIR/Failed/"
            log_main "PRELIM DICOM $BASENAME -> Failed/ | filename missing underscore"
            continue
        fi

        AET="${BASENAME%%_*}"
        AET="${AET%.dcm}"
        UNCOMPRESSED_FILE="${NEW_DICOM_FILE%.dcm}_uncompressed.dcm"

        if dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE" >> "$LOG_PRELIMSR" 2>&1; then
            if storescu -v -aet "$AET" -aec "$PRELIM_AEC" "$DICOM_HOST" "$DICOM_PORT" "$UNCOMPRESSED_FILE" >> "$LOG_PRELIMSR" 2>&1; then
                rm -f "$UNCOMPRESSED_FILE"
                mkdir -p "$PRELIM_DICOM_DIR/Processed"
                mv "$NEW_DICOM_FILE" "$PRELIM_DICOM_DIR/Processed/"
                log_main "PRELIM DICOM $BASENAME -> Processed/ | AET=$AET sent ok"
            else
                mkdir -p "$PRELIM_DICOM_DIR/Failed"
                mv "$UNCOMPRESSED_FILE" "$PRELIM_DICOM_DIR/Failed/"
                log_main "PRELIM DICOM $BASENAME -> Failed/ | AET=$AET send err"
            fi
        else
            mkdir -p "$PRELIM_DICOM_DIR/Failed"
            mv "$NEW_DICOM_FILE" "$PRELIM_DICOM_DIR/Failed/"
            log_main "PRELIM DICOM $BASENAME -> Failed/ | uncompress err"
        fi
    done
}

# Run all three monitors in parallel
monitor_root &
monitor_hl7_dicom &
monitor_prelim_dicom &
wait
