import base64
import os
import re
import subprocess
import shutil
import sys
import logging
import time
from pdf2image import convert_from_path

# Converts HL7 files containing base64-encoded PDF data in OBX-5 segments to PDF, then to JPEG, and finally to DICOM format.
# Use case: Convert preliminary reports from nighthawk providers to DICOM format for PACS posting when RIS cannot accept prelims.
# Generated PDFs can be used for automated faxing (see ORU2pdf.py), encrypted email distribution, Samba network folder drops, or Azure API uploads to SharePoint.
# Updated: Accepts file path as command-line argument instead of polling directory for improved efficiency.

# Setup logging to print to terminal
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# Directory paths (relative to script location or absolute)
# These can be overridden via environment variables
base_dir = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
hl7_dir = os.path.join(base_dir, "HL7/")
pdf_dir = os.path.join(base_dir, "PDFs/")
dcm_dir = os.path.join(base_dir, "DICOM/")
error_dir = os.path.join(base_dir, "pdf2dcmERROR/")
jpeg_dir = os.path.join(base_dir, "JPEGs/")

# Ensure directories exist
os.makedirs(hl7_dir, exist_ok=True)
os.makedirs(pdf_dir, exist_ok=True)
os.makedirs(dcm_dir, exist_ok=True)
os.makedirs(error_dir, exist_ok=True)
os.makedirs(jpeg_dir, exist_ok=True)

def wait_for_file_complete(file_path, max_wait=30, check_interval=0.5):
    """Wait for file to be completely written (file size stable)."""
    if not os.path.exists(file_path):
        return False
    
    last_size = -1
    stable_count = 0
    required_stable = 2  # File size must be stable for 2 checks
    
    for _ in range(int(max_wait / check_interval)):
        try:
            current_size = os.path.getsize(file_path)
            if current_size == last_size:
                stable_count += 1
                if stable_count >= required_stable:
                    return True
            else:
                stable_count = 0
                last_size = current_size
            time.sleep(check_interval)
        except OSError:
            return False
    return False

def parse_hl7(hl7_message):
    pid_5, pid_3, pid_7, obr_3, obr_4_2, obx_11 = None, None, None, None, None, None
    base64_pdf = ""

    lines = hl7_message.split("\n")
    for line in lines:
        if line.startswith("PID"):
            pid_5_match = re.search(r"(?:\|[^|]*){4}\|([^|]*)", line)
            pid_3_match = re.search(r"(?:\|[^|]*){2}\|([^|]*)", line)
            pid_7_match = re.search(r"(?:\|[^|]*){6}\|([^|]*)", line)
            if pid_5_match: pid_5 = pid_5_match.group(1).strip()
            if pid_3_match: pid_3 = pid_3_match.group(1).strip()
            if pid_7_match: pid_7 = pid_7_match.group(1).strip()

        if line.startswith("OBR"):
            obr_3_match = re.search(r"(?:\|[^|]*){2}\|([^|]*)", line)
            obr_4_match = re.search(r"(?:\|[^|]*){3}\|([^|]*)", line)
            if obr_3_match: obr_3 = obr_3_match.group(1).strip()
            if obr_4_match:
                obr_4_parts = obr_4_match.group(1).split("^")
                if len(obr_4_parts) > 1:
                    obr_4_2 = obr_4_parts[1][:2].strip()

        if line.startswith("OBX"):
            obx_11_match = re.search(r"(?:\|[^|]*){10}\|([^|]*)", line)
            if obx_11_match: obx_11 = obx_11_match.group(1).strip()
            parts = line.split("|")
            if len(parts) > 5:
                base64_pdf += parts[5].strip()

    return pid_5, pid_3, pid_7, obr_3, obr_4_2, obx_11, base64_pdf

def process_hl7_file(hl7_file_path):
    """Process a single HL7 file. Returns True on success, False on error."""
    # Initialize variables for error reporting
    pid_5 = pid_3 = pid_7 = obr_3 = obr_4_2 = obx_11 = None
    
    logging.info(f"Processing file: {hl7_file_path}")
    
    # Check if file exists and is readable
    if not os.path.exists(hl7_file_path):
        logging.error(f"File does not exist: {hl7_file_path}")
        return False
    
    if not os.access(hl7_file_path, os.R_OK):
        logging.error(f"File is not readable: {hl7_file_path}")
        return False
    
    # Wait for file to be completely written
    if not wait_for_file_complete(hl7_file_path):
        logging.warning(f"File may still be writing: {hl7_file_path}, proceeding anyway")
    
    try:
        with open(hl7_file_path, "r", encoding='utf-8', errors='ignore') as file:
            hl7_message = file.read()

        if not hl7_message.strip():
            raise ValueError("HL7 file is empty")

        pid_5, pid_3, pid_7, obr_3, obr_4_2, obx_11, base64_pdf = parse_hl7(hl7_message)

        # Validate required fields early
        if not all([pid_5, pid_3, pid_7, obr_3, obr_4_2, obx_11]):
            missing = []
            if not pid_5: missing.append("PID-5 (Patient Name)")
            if not pid_3: missing.append("PID-3 (Patient ID)")
            if not pid_7: missing.append("PID-7 (Patient DOB)")
            if not obr_3: missing.append("OBR-3 (Accession Number)")
            if not obr_4_2: missing.append("OBR-4-2 (Modality)")
            if not obx_11: missing.append("OBX-11")
            raise ValueError(f"Missing required fields: {', '.join(missing)}")

        safe_pid_5 = re.sub(r'[^\w\-]', '_', pid_5) if pid_5 else "UNKNOWN"
        safe_pid_3 = re.sub(r'[^\w\-]', '_', pid_3) if pid_3 else "UNKNOWN"
        safe_obr_3 = re.sub(r'[^\w\-]', '_', obr_3) if obr_3 else "UNKNOWN"

        output_pdf_name = f"{safe_pid_5}_{safe_pid_3}_{safe_obr_3}.pdf"
        output_pdf_path = os.path.join(pdf_dir, output_pdf_name)

        output_jpg_name = f"{safe_pid_5}_{safe_pid_3}_{safe_obr_3}.jpg"
        output_jpg_path = os.path.join(jpeg_dir, output_jpg_name)

        output_dcm_name = f"{safe_pid_5}_{safe_pid_3}_{safe_obr_3}.dcm"
        output_dcm_path = os.path.join(dcm_dir, output_dcm_name)

        # Step 1: Decode Base64 PDF
        if not base64_pdf:
            raise ValueError("No base64 PDF data found in HL7 message")
        
        base64_pdf_cleaned = base64_pdf.replace("^^PDF^Base64^", "").replace("\n", "").replace("\r", "")
        padding_needed = len(base64_pdf_cleaned) % 4
        if padding_needed:
            base64_pdf_cleaned += "=" * (4 - padding_needed)

        try:
            pdf_binary = base64.b64decode(base64_pdf_cleaned)
        except Exception as e:
            raise ValueError(f"Failed to decode base64 PDF: {e}")

        with open(output_pdf_path, "wb") as pdf_file:
            pdf_file.write(pdf_binary)
        logging.info(f"PDF successfully saved as {output_pdf_path}")

        # Step 2: Convert PDF to JPEG
        try:
            images = convert_from_path(output_pdf_path, dpi=200, first_page=1, last_page=1)
            if not images:
                raise ValueError("No pages found in PDF for JPEG conversion.")
            images[0].save(output_jpg_path, 'JPEG')
            logging.info(f"JPEG created: {output_jpg_path}")
        except Exception as e:
            raise ValueError(f"Failed to convert PDF to JPEG: {e}")

        # Step 3: Convert JPEG to DICOM
        img2dcm_command = [
            'img2dcm',
            '-k', f'(0010,0010)={pid_5}',     # Patient Name
            '-k', f'(0010,0020)={pid_3}',     # Patient ID
            '-k', f'(0010,0030)={pid_7}',     # Patient DOB
            '-k', f'(0010,0040)={obx_11}',    # Patient Sex (or other value stored in OBX-11)
            '-k', f'(0008,0050)={obr_3}',     # Accession Number
            '-k', f'(0008,0060)={obr_4_2}',   # Modality
            output_jpg_path,
            output_dcm_path
        ]

        try:
            result = subprocess.run(img2dcm_command, check=True, capture_output=True, text=True)
            logging.info(f"DICOM file created: {output_dcm_path}")
        except subprocess.CalledProcessError as e:
            raise ValueError(f"img2dcm failed: {e.stderr if e.stderr else str(e)}")

        # Move processed file to archive
        shutil.move(hl7_file_path, os.path.join(hl7_dir, os.path.basename(hl7_file_path)))
        logging.info(f"Moved HL7 file to {hl7_dir}")
        return True

    except Exception as e:
        logging.error(f"Error processing file {hl7_file_path}: {e}")
        logging.error(f"PID-5: {pid_5}")
        logging.error(f"PID-3: {pid_3}")
        logging.error(f"PID-7: {pid_7}")
        logging.error(f"OBR-3: {obr_3}")
        logging.error(f"OBR-4-2: {obr_4_2}")
        logging.error(f"OBX-11: {obx_11}")
        
        # Move error file
        try:
            shutil.move(hl7_file_path, os.path.join(error_dir, os.path.basename(hl7_file_path)))
            logging.info(f"Moved error file to {error_dir}")
        except Exception as move_error:
            logging.error(f"Failed to move error file: {move_error}")
        return False

if __name__ == "__main__":
    if len(sys.argv) < 2:
        logging.error("Usage: python3 hl7_pdf_dcm_optimized.py <hl7_file_path>")
        logging.error("This script processes a single HL7 file provided as an argument.")
        logging.error("For directory monitoring, use filemonitor.sh with inotifywait.")
        sys.exit(1)
    
    hl7_file_path = sys.argv[1]
    success = process_hl7_file(hl7_file_path)
    sys.exit(0 if success else 1)