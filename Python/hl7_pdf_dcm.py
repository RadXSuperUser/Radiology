import base64
import os
import re
import subprocess
import shutil
import time
import logging
from pdf2image import convert_from_path
from PIL import Image
# Script to convert HL7 files to PDF, then to JPEG, and finally to DICOM format.

# Setup logging to print to terminal
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)

# Directory paths
input_dir = "/TargetDIR"
hl7_dir = "HL7/"
pdf_dir = "PDFs/"
dcm_dir = "DICOM/"
error_dir = "pdf2dcmERROR/"
jpeg_dir = "JPEGs/"

# Ensure directories exist
os.makedirs(input_dir, exist_ok=True)
os.makedirs(hl7_dir, exist_ok=True)
os.makedirs(pdf_dir, exist_ok=True)
os.makedirs(dcm_dir, exist_ok=True)
os.makedirs(error_dir, exist_ok=True)
os.makedirs(jpeg_dir, exist_ok=True)

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

    return pid_5, pid_3, pid_7, obr_3,obr_4_2, obx_11, base64_pdf

def process_hl7_file(hl7_file_path):
    logging.info(f"Processing file: {hl7_file_path}")
    try:
        with open(hl7_file_path, "r") as file:
            hl7_message = file.read()

        pid_5, pid_3, pid_7, obr_3, obr_4_2, obx_11, base64_pdf = parse_hl7(hl7_message)

        safe_pid_5 = re.sub(r'[^\w\-]', '_', pid_5)
        safe_pid_3 = re.sub(r'[^\w\-]', '_', pid_3)
        safe_obr_3 = re.sub(r'[^\w\-]', '_', obr_3)

        output_pdf_name = f"{safe_pid_5}_{safe_pid_3}_{safe_obr_3}.pdf"
        output_pdf_path = os.path.join(pdf_dir, output_pdf_name)

        output_jpg_name = f"{safe_pid_5}_{safe_pid_3}_{safe_obr_3}.jpg"
        output_jpg_path = os.path.join(jpeg_dir, output_jpg_name)

        output_dcm_name = f"{safe_pid_5}_{safe_pid_3}_{safe_obr_3}.dcm"
        output_dcm_path = os.path.join(dcm_dir, output_dcm_name)

        # Step 1: Decode Base64 PDF
        base64_pdf_cleaned = base64_pdf.replace("^^PDF^Base64^", "").replace("\n", "").replace("\r", "")
        padding_needed = len(base64_pdf_cleaned) % 4
        if padding_needed:
            base64_pdf_cleaned += "=" * (4 - padding_needed)

        pdf_binary = base64.b64decode(base64_pdf_cleaned)
        with open(output_pdf_path, "wb") as pdf_file:
            pdf_file.write(pdf_binary)
        logging.info(f"PDF successfully saved as {output_pdf_path}")

        # Step 2: Convert PDF to JPEG
        images = convert_from_path(output_pdf_path, dpi=200, first_page=1, last_page=1)
        if not images:
            raise ValueError("No pages found in PDF for JPEG conversion.")
        images[0].save(output_jpg_path, 'JPEG')
        logging.info(f"JPEG created: {output_jpg_path}")

        # Step 3: Convert JPEG to DICOM
        if not all([pid_5, pid_3, pid_7, obr_3, obr_4_2, obx_11]):
            raise ValueError("Missing required fields in HL7 message.")

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

        subprocess.run(img2dcm_command, check=True)
        logging.info(f"DICOM file created: {output_dcm_path}")

        shutil.move(hl7_file_path, os.path.join(hl7_dir, os.path.basename(hl7_file_path)))
        logging.info(f"Moved HL7 file to {hl7_dir}")

    except Exception as e:
        logging.error(f"Error processing file {hl7_file_path}: {e}")
        logging.error(f"PID-5: {pid_5}")
        logging.error(f"PID-3: {pid_3}")
        logging.error(f"PID-7: {pid_7}")
        logging.error(f"OBR-3: {obr_3}")
        logging.error(f"OBR-4-2: {obr_4_2}")
        logging.error(f"OBX-11: {obx_11}")
        shutil.move(hl7_file_path, os.path.join(error_dir, os.path.basename(hl7_file_path)))
        logging.info(f"Moved error file to {error_dir}")

def monitor_directory():
    initial_run = True
    while True:
        hl7_files = [
            f for f in os.listdir(input_dir)
            if os.path.isfile(os.path.join(input_dir, f))
            and not f.startswith("FAX_")
            and not f.endswith((".sh", ".py", ".log"))
        ]

        if not hl7_files:
            if initial_run:
                logging.info("No more HL7 files found. Waiting for 5 seconds for inbounds.")
                time.sleep(5)
                initial_run = False
            else:
                logging.info("No new HL7 files received. Exiting script.")
                break
        else:
            initial_run = True  # Reset after processing files
            for hl7_file in hl7_files:
                hl7_file_path = os.path.join(input_dir, hl7_file)
                process_hl7_file(hl7_file_path)

if __name__ == "__main__":
    logging.info(f"Scanning directory: {input_dir} for HL7 files.")
    monitor_directory()