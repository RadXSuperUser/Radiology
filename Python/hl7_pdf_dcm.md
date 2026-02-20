# HL7 to PDF to DICOM Converter

## Overview

`hl7_pdf_dcm.py` converts HL7 files containing base64-encoded PDF data in OBX-5 segments through a multi-step conversion process:

1. **PDF Extraction**: Decodes base64-encoded PDF data from OBX-5 segments
2. **JPEG Conversion**: Converts the first page of the PDF to JPEG format
3. **DICOM Creation**: Converts the JPEG to DICOM format with patient and study metadata

## Use Case

This script addresses scenarios where a Radiology Information System (RIS) cannot accept preliminary report formats from nighthawk providers. The solution converts preliminary reports to DICOM format for posting in PACS (Picture Archiving and Communication System).

### Additional PDF Use Cases

The generated PDFs can be utilized for:
- **Automated Faxing**: See `ORU2pdf.py` for fax integration
- **Encrypted Email Distribution**: Secure transmission of reports
- **Samba Network Folder Drops**: Automated file sharing via network shares
- **Azure API SharePoint Uploads**: Cloud-based document management

## How It Works

### Processing Flow

1. **Input**: Accepts an HL7 file path as a command-line argument
2. **Parsing**: Extracts required patient and study information from HL7 segments:
   - Patient demographics (PID segment)
   - Study information (OBR segment)
   - Base64 PDF data (OBX segment)
3. **File Generation**: Creates three output files:
   - PDF file in `PDFs/` directory
   - JPEG file in `JPEGs/` directory
   - DICOM file in `DICOM/` directory
4. **File Management**: Moves processed HL7 files to `HL7/` archive directory, or error files to `pdf2dcmERROR/` directory

### Current HL7 Segment Mapping

The script extracts the following HL7 fields:

| HL7 Field | Description | Used For |
|-----------|-------------|----------|
| PID-5 | Patient Name | DICOM tag (0010,0010) |
| PID-3 | Patient ID | DICOM tag (0010,0020) |
| PID-7 | Patient Date of Birth | DICOM tag (0010,0030) |
| OBR-3 | Accession Number | DICOM tag (0008,0050) |
| OBR-4-2 | Modality (2nd component) | DICOM tag (0008,0060) |
| OBX-11 | Patient Sex (or other value) | DICOM tag (0010,0040) |
| OBX-5 | Base64-encoded PDF data | PDF extraction |

## Customization Guide

Different HL7 implementations may use different field positions or segments. This guide explains how to customize the script for your environment.

### Understanding the Code Structure

The customization involves three main areas:

1. **`parse_hl7()` function** (lines 90-120): Extracts data from HL7 segments using regex patterns
2. **`process_hl7_file()` function** (lines 122-215): Validates extracted data and maps it to DICOM tags
3. **DICOM tag mapping** (lines 177-186): Assigns extracted values to DICOM metadata tags

### Step-by-Step Customization

#### 1. Modify Field Extraction in `parse_hl7()`

The regex patterns use the format `(?:\|[^|]*){N}\|([^|]*)` where `N` is the number of fields to skip before the target field.

**Example Pattern Breakdown:**
- `(?:\|[^|]*){4}\|` - Skip 4 fields (positions 1-4), then capture the 5th field
- `([^|]*)` - Capture everything until the next pipe character

**For component extraction** (like OBR-4-2), the code splits on `^`:
```python
obr_4_parts = obr_4_match.group(1).split("^")
if len(obr_4_parts) > 1:
    obr_4_2 = obr_4_parts[1][:2].strip()
```

#### 2. Update DICOM Tag Mapping

In the `img2dcm_command` list (lines 177-186), modify the `-k` parameters to map your extracted values to the appropriate DICOM tags:

```python
'-k', f'(0010,0010)={pid_5}',     # Patient Name
'-k', f'(0010,0020)={pid_3}',     # Patient ID
# ... etc
```

#### 3. Update Validation

If you add new required fields, update the validation section (lines 152-159) to include checks for those fields.

#### 4. Handle Multiple Segments

The current code concatenates OBX-5 fields from all OBX segments. If your implementation requires different handling, modify the OBX parsing logic accordingly.

## Customization Examples

### Example 1: Using PID-18 (Alternative Patient ID) Instead of PID-3

**Scenario**: Your HL7 messages use PID-18 (Patient Account Number) as the primary patient identifier instead of PID-3.

**Changes Required**:

1. **Update `parse_hl7()` function** - Modify line 98:
   ```python
   # Original (extracts PID-3):
   pid_3_match = re.search(r"(?:\|[^|]*){2}\|([^|]*)", line)
   
   # Changed to extract PID-18 (skip 17 fields):
   pid_3_match = re.search(r"(?:\|[^|]*){17}\|([^|]*)", line)
   ```

2. **Update error reporting** (optional, for clarity) - Modify line 155:
   ```python
   # Original:
   if not pid_3: missing.append("PID-3 (Patient ID)")
   
   # Updated:
   if not pid_3: missing.append("PID-18 (Patient Account Number)")
   ```

**Note**: The variable name `pid_3` can remain the same since it's just a variable name. The important change is the regex pattern that determines which field is extracted.

### Example 2: Extracting Patient Sex from PID-8 Instead of OBX-11

**Scenario**: Your HL7 messages store Patient Sex in PID-8 (standard HL7 location) rather than OBX-11.

**Changes Required**:

1. **Update `parse_hl7()` function** - Add extraction for PID-8 in the PID segment block (around line 96-102):
   ```python
   if line.startswith("PID"):
       pid_5_match = re.search(r"(?:\|[^|]*){4}\|([^|]*)", line)
       pid_3_match = re.search(r"(?:\|[^|]*){2}\|([^|]*)", line)
       pid_7_match = re.search(r"(?:\|[^|]*){6}\|([^|]*)", line)
       pid_8_match = re.search(r"(?:\|[^|]*){7}\|([^|]*)", line)  # NEW: Extract PID-8
       if pid_5_match: pid_5 = pid_5_match.group(1).strip()
       if pid_3_match: pid_3 = pid_3_match.group(1).strip()
       if pid_7_match: pid_7 = pid_7_match.group(1).strip()
       if pid_8_match: pid_8 = pid_8_match.group(1).strip()  # NEW: Store PID-8
   ```

2. **Update function signature and return** - Modify line 90 and 120:
   ```python
   # Line 90: Change function signature
   def parse_hl7(hl7_message):
       pid_5, pid_3, pid_7, obr_3, obr_4_2, pid_8 = None, None, None, None, None, None  # Changed obx_11 to pid_8
       base64_pdf = ""
       # ... rest of function ...
   
   # Line 120: Update return statement
   return pid_5, pid_3, pid_7, obr_3, obr_4_2, pid_8, base64_pdf  # Changed obx_11 to pid_8
   ```

3. **Update `process_hl7_file()` function** - Modify line 125 and 149:
   ```python
   # Line 125: Update variable initialization
   pid_5 = pid_3 = pid_7 = obr_3 = obr_4_2 = pid_8 = None  # Changed obx_11 to pid_8
   
   # Line 149: Update unpacking
   pid_5, pid_3, pid_7, obr_3, obr_4_2, pid_8, base64_pdf = parse_hl7(hl7_message)  # Changed obx_11 to pid_8
   ```

4. **Update validation** - Modify lines 152 and 159:
   ```python
   # Line 152: Update validation check
   if not all([pid_5, pid_3, pid_7, obr_3, obr_4_2, pid_8]):  # Changed obx_11 to pid_8
       missing = []
       # ... other checks ...
       if not pid_8: missing.append("PID-8 (Patient Sex)")  # Changed OBX-11 to PID-8
   ```

5. **Update DICOM mapping** - Modify line 182:
   ```python
   # Line 182: Update DICOM tag assignment
   '-k', f'(0010,0040)={pid_8}',    # Patient Sex (changed from obx_11 to pid_8)
   ```

6. **Update error reporting** - Modify line 207:
   ```python
   # Line 207: Update error logging
   logging.error(f"PID-8: {pid_8}")  # Changed OBX-11 to PID-8
   ```

## Usage

```bash
python3 hl7_pdf_dcm.py <hl7_file_path>
```

**Example**:
```bash
python3 hl7_pdf_dcm.py /path/to/report.hl7
```

For directory monitoring and automated processing, use `filemonitor.sh` with `inotifywait` to watch for new HL7 files and call this script automatically.

## Requirements

- Python 3.x
- `pdf2image` library (requires Poppler)
- DCMTK toolkit (for `img2dcm` command)
- Appropriate directory permissions for file creation and movement

## Output Directories

The script creates and uses the following directories (relative to script location):
- `HL7/` - Archive for processed HL7 files
- `PDFs/` - Generated PDF files
- `JPEGs/` - Generated JPEG files
- `DICOM/` - Generated DICOM files
- `pdf2dcmERROR/` - Error files that failed processing
