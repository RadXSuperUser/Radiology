# Radiology Relay Pipeline – Architecture, Deployment, and Customization

This document describes how the following components work together to form a simple “relay” service that accepts text/HL7/json inputs and delivers DICOM objects and PDFs into PACS or downstream workflows:

- `BASH/filemonitor.sh`
- `Python/hl7_pdf_dcm.py`
- `Python/prelimSR.py`
- `Python/ORU2pdf.py`

It also covers how to deploy this stack on a Linux host, and how to customize each script for different environments, including non‑Intelerad and single‑facility setups.

---

## 1. High‑Level Architecture

At a high level, the system behaves like this:

1. **filemonitor.sh**  
   - Watches a “drop” directory (`/var/lib/filemonitor`) for new files.  
   - Looks at the filename pattern to decide what the file is (FAX JSON, prelim JSON, HL7, etc.).  
   - Moves files into workflow‑specific subdirectories and calls the appropriate Python script.  
   - Watches DICOM output directories and pushes finished DICOMs to PACS using DCMTK `storescu`.

2. **ORU2pdf.py**  
   - Converts ORU style text/JSON messages (for example, FAX reports) to **PDF**, and optionally renames them using values such as fax number and accession number.

3. **hl7_pdf_dcm.py**  
   - Accepts a single HL7 file (with base64 PDF in OBX‑5).  
   - Extracts and decodes the embedded PDF, converts it to JPEG, then converts that JPEG to a DICOM object suitable for PACS ingestion.

4. **prelimSR.py**  
   - Accepts JSON ORU‑like data and produces a **DICOM SR** (Structured Report) object.  
   - Is explicitly designed for **Intelerad multi‑facility environments** and makes the JSON `Facility` key mandatory so that SRs are correctly grouped into the right Intelerad facility/site.

Each Python script has its own dedicated log file; `filemonitor.sh` keeps a small, high‑signal main log that focuses on:

- which file was received,
- which handler script ran,
- which directory the file was moved to,
- and whether the send to PACS succeeded or failed.

---

## 2. Component Responsibilities and Data Flow

### 2.1 `filemonitor.sh`

**Role:** Central orchestrator and DICOM relay.

**Key responsibilities:**

- Watch a root directory:
  - `MONITOR_DIR="/var/lib/filemonitor"`
- Route new files based on their names:
  - `FAX_*.json`  → FAX workflow (`/var/lib/filemonitor/FAX`) → `ORU2pdf.py`
  - `PRELIM_*`    → Prelim workflow (`/var/lib/filemonitor/PrelimSR`) → `prelimSR.py`
  - Other HL7‑style files → HL7 workflow → `hl7_pdf_dcm.py`
- Watch DICOM output directories:
  - HL7toDICOM DICOM files → DCMTK `dcmdjpeg` + `storescu`
  - PrelimSR DICOM SR files → DCMTK `storescu` (no `dcmdjpeg` needed)

**Main pieces:**

- **Root monitor (`monitor_root`)**
  - Uses `inotifywait` on `MONITOR_DIR` for `close_write` / `moved_to`.
  - Ignores temp files (`*.swp`, `*.tmp`, `*~`, etc.).
  - Only handles files that appear directly under `/var/lib/filemonitor` (not subdirectories).
  - Based on basename:
    - `FAX_*.json`:
      - Moves file to `/var/lib/filemonitor/FAX/`.
      - Calls `/opt/ORU2pdf.py`.
    - `PRELIM_*`:
      - Moves file to `/var/lib/filemonitor/PrelimSR/`.
      - Calls `/opt/prelimSR.py <moved_file>`.
    - Other files:
      - Treated as HL7 inputs and passed to `/opt/hl7toDICOM.py <file>` (which internally runs `hl7_pdf_dcm.py` logic).

- **HL7 DICOM monitor (`monitor_hl7_dicom`)**
  - Watches `/var/lib/filemonitor/HL7toDICOM` (and its DICOM subdirectory).
  - For each new DICOM:
    - Runs `dcmdjpeg` to uncompress the file if needed.
    - Sends it to PACS using `storescu` (`DICOM_AET`, `DICOM_AEC`, `DICOM_HOST`, `DICOM_PORT`).  
    - Moves success to `HL7toDICOM/Processed/`, failure to `HL7toDICOM/Failed/`.

- **Prelim DICOM monitor (`monitor_prelim_dicom`)**
  - Watches `/var/lib/filemonitor/PrelimSR/DICOM`.
  - Infers the AE Title to use from the filename:
    - `BASENAME="SITEA_123456.dcm"` → `AET="SITEA"`.
  - Sends SR DICOM directly via `storescu` (no `dcmdjpeg`, SRs are written uncompressed by `prelimSR.py`).
  - On success: moves to `PrelimSR/DICOM/Processed/`.  
    On failure: moves to `PrelimSR/DICOM/Failed/`.

**Logging:**

- **Main log:** `/opt/FileMonitor.log`
  - Only high‑level routing and send results, for example:
    - `RECV FAX FAX_123.json -> /var/lib/filemonitor/FAX | script ORU2pdf.py`
    - `DONE ORU2pdf.py FAX_123.json ok`
    - `PRELIM DICOM SITEA_123456.dcm -> Processed/ | AET=SITEA sent ok`
- **Per‑script logs:**
  - `/var/lib/filemonitor/FAX/logs/ORU2pdf.log`
  - `/var/lib/filemonitor/PrelimSR/logs/prelimSR.log`
  - `/var/lib/filemonitor/HL7toDICOM/logs/hl7_pdf_dcm.log`

Each Python script is responsible for its detailed logging; `filemonitor.sh` doesn’t “tee” their entire output into the main log.

---

### 2.2 `hl7_pdf_dcm.py`

**Role:** Convert HL7 messages with embedded base64 PDF into DICOM images.

**Standard flow:**

1. **Input:** A single HL7 file path (`hl7_file_path`) passed on the command line.
2. **Parsing (PID / OBR / OBX):**
   - `PID`:
     - PID‑5 → Patient Name
     - PID‑3 → Patient ID
     - PID‑7 → Date of Birth
   - `OBR`:
     - OBR‑3 → Accession Number
     - OBR‑4‑2 → Modality (2nd `^` component)
   - `OBX`:
     - OBX‑11 → used as Patient Sex or similar value
     - OBX‑5 → concatenated base64 PDF payload
3. **PDF creation:**
   - Cleans base64 payload, fixes padding, decodes to binary, and writes a PDF under:
     - `/var/lib/filemonitor/HL7toDICOM/PDFs/`
4. **JPEG creation:**
   - Uses `pdf2image.convert_from_path` to render the first PDF page to JPEG:
     - `/var/lib/filemonitor/HL7toDICOM/JPEGs/`
5. **DICOM creation:**
   - Calls DCMTK `img2dcm` with `-k` overrides to embed patient/study metadata:
     - `/var/lib/filemonitor/HL7toDICOM/DICOM/`
6. **File disposition:**
   - On success: HL7 input is moved to `/var/lib/filemonitor/HL7toDICOM/HL7/`.
   - On error: HL7 input is moved to `/var/lib/filemonitor/HL7toDICOM/pdf2dcmERROR/`.

`filemonitor.sh` then picks up new `.dcm` files under the HL7toDICOM DICOM directory and sends them to PACS.

**Logging:**

- Writes to `/var/lib/filemonitor/HL7toDICOM/logs/hl7_pdf_dcm.log` via the Python `logging` module.

---

### 2.3 `prelimSR.py`

**Role:** Convert JSON ORU‑style data into a DICOM SR document.

**Inputs and expectations:**

- Invoked as:

```bash
python3 prelimSR.py /var/lib/filemonitor/PrelimSR/PRELIM_*.json
```

- The JSON is expected to contain (among other keys):
  - `Accession`
  - `Facility`  **(Intelerad‑specific requirement – see below)**
  - `ExamType`
  - `Ordering`, `Radiologist`, `Report`
  - Optional: `SUID` (existing StudyInstanceUID or site‑specific code)

**Core behavior:**

1. **Validation:**
   - Exits with error if `Accession` or `Facility` keys are missing.
2. **PACS StudyInstanceUID lookup (Intelerad‑style):**
   - Uses DCMTK `findscu` to query PACS:
     - Query key: `AccessionNumber (0008,0050) = <Accession><Facility>`
   - If a `StudyInstanceUID` is returned, it is written back into the JSON as `SUID`.
   - If the PACS cannot be reached or the association times out, the script logs it and continues with a generated UID.
3. **DICOM SR creation:**
   - Builds a Basic Text SR‑like DICOM object using `pydicom`:
     - `StudyInstanceUID`:
       - from `SUID` (if present), otherwise generated.
     - `AccessionNumber`, `StudyID` from `Accession`.
     - `StudyDescription` from `ExamType`.
     - `InstitutionName` from `Facility`.
     - Referring and reading physicians from `Ordering` and `Radiologist`.
     - `Report` text becomes the SR content tree.
4. **Output and file moves:**
   - Initial SR is written next to the input JSON as:
     - `<Facility>_<Accession>.dcm`
   - Then moved into:
     - DICOM SR: `/var/lib/filemonitor/PrelimSR/DICOM/<Facility>_<Accession>.dcm`
     - JSON archive: `/var/lib/filemonitor/PrelimSR/JSON/<original_json>.json`

`filemonitor.sh` monitors `/var/lib/filemonitor/PrelimSR/DICOM` and, based on filename (e.g. `SITEA_123456.dcm`), infers an AE Title from the prefix before `_` to send to a facility‑specific PACS AE.

**Logging:**

- Writes to `/var/lib/filemonitor/PrelimSR/logs/prelimSR.log` via the Python `logging` module.

---

### 2.4 `ORU2pdf.py`

**Role:** Convert ORU‑structured text/JSON into PDFs, typically for fax or downstream document workflows.

**Flow:**

1. **Working directories:**
   - `directory = "/var/lib/filemonitor/FAX"`
   - `pdf_dir = "/var/lib/filemonitor/FAX/pdf"`
   - `json_dir = "/var/lib/filemonitor/FAX/json"`
2. **Step 1 – Text→JSON:**
   - Renames `*.txt` files in `directory` to `*.json` (simple extension change) for easier parsing.
3. **Step 2 – JSON→PDF:**
   - Reads each JSON file, flattens nested data into text lines, and feeds a `pdfme` layout definition.
   - Uses a logo image, e.g. `/opt/radx-workflow/photos/radxsulogo.png`, in the PDF header.
4. **Step 3 – PDF renaming:**
   - Uses JSON keys to rename the PDFs:
     - `fax_key = "Fax"`
     - `accn_key = "Accession"`
   - New filename pattern:

     ```text
     fax={1<fax_number_no_dashes>}ACCN-<Accession>.pdf
     ```

5. **Archival:**
   - Moves processed JSONs to `json_dir`.

**Logging:**

- Writes to `/var/lib/filemonitor/FAX/logs/ORU2pdf.log` via `logging`.

---

## 3. Deployment on a Linux Host

This stack is designed to be straightforward to deploy on a typical Linux box (physical server or VM) and can serve as either a **temporary bridge** (e.g., during RIS/PACS migration) or a **long‑term relay**.

### 3.1 System Dependencies

At minimum, you need:

- **System packages:**
  - `inotify-tools` (for `inotifywait`)
  - `dcmtk` (for `storescu`, `dcmdjpeg`, `img2dcm`)
  - `poppler-utils` (for `pdf2image` PDF rendering)
  - A recent `python3`

Example (Debian/Ubuntu‑like):

```bash
sudo apt-get update
sudo apt-get install -y inotify-tools dcmtk poppler-utils python3 python3-venv
```

- **Python packages (in a virtualenv or system‑wide):**
  - `pydicom`
  - `pdf2image`
  - `pdfme`
  - `chardet`
  - `Pillow` (required by `pdf2image`)

```bash
python3 -m venv /opt/radx-workflow
/opt/radx-workflow/bin/pip install pydicom pdf2image pdfme chardet pillow
```

Make sure `filemonitor.sh` points to the correct Python interpreter, for example:

```bash
/opt/radx-workflow/bin/python -u "$FAX_SCRIPT"
/opt/radx-workflow/bin/python -u "$PRELIM_SCRIPT" "$MOVED_FILE"
/opt/radx-workflow/bin/python -u "$HL7toDICOM_SCRIPT" "$NEW_FILE"
```

### 3.2 Directory Layout

Recommended directories (matching the current scripts):

- `/var/lib/filemonitor` – main incoming directory:
  - `FAX/` – FAX JSON/ORU inputs, PDF outputs.
  - `PrelimSR/` – prelim JSON inputs, SR DICOM and JSON archive.
  - `HL7toDICOM/` – HL7 inputs, PDFs, JPEGs, DICOM, error files.
- `/opt` – deployment location for Python scripts:
  - `/opt/ORU2pdf.py`
  - `/opt/prelimSR.py`
  - `/opt/hl7toDICOM.py` (wrapper around `hl7_pdf_dcm.py`)
  - `/opt/radx-workflow/bin/python` – virtualenv python.

Make sure log directories exist or are created by the scripts:

- `/var/lib/filemonitor/FAX/logs`
- `/var/lib/filemonitor/PrelimSR/logs`
- `/var/lib/filemonitor/HL7toDICOM/logs`

### 3.3 Running `filemonitor.sh` as a Service

You can run `filemonitor.sh`:

- manually in a screen/tmux session, or
- as a `systemd` service for production use.

Minimal `systemd` unit example:

```ini
[Unit]
Description=Radiology File Monitor Relay
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /opt/filemonitor.sh
Restart=on-failure
User=filemonitor
Group=filemonitor

[Install]
WantedBy=multi-user.target
```

After creating `/etc/systemd/system/filemonitor.service`:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now filemonitor.service
```

---

## 4. Environment‑Specific Customization

### 4.1 Customizing `filemonitor.sh`

You will commonly adjust:

- **Watch directory:**
  - `MONITOR_DIR="/var/lib/filemonitor"`  
    Change if your integration engine deposits files elsewhere.
- **Script paths:**
  - `FAX_SCRIPT="/opt/ORU2pdf.py"`
  - `PRELIM_SCRIPT="/opt/prelimSR.py"`
  - `HL7toDICOM_SCRIPT="/opt/hl7toDICOM.py"`
- **DICOM send config:**
  - `DICOM_HOST`, `DICOM_PORT`
  - `DICOM_AET`, `DICOM_AEC`
  - `PRELIM_AEC` (target AEC for SR posting)
- **Filename patterns:**
  - `FAX_*.json`, `PRELIM_*` can be changed to match your upstream naming (e.g., `FAXOUT_*.json`, `SRPRELIM_*`).

Example – single‑facility, no site‑specific AET in the filename:

- If your prelim DICOM filenames do **not** encode the AET in their prefix (e.g., just `123456.dcm`), you can:
  - remove the AET extraction from `monitor_prelim_dicom`, and
  - use a fixed AE Title instead:

```bash
# Instead of deriving AET from BASENAME:
# AET="${BASENAME%%_*}"

AET="PRELIM_SENDER"
```

### 4.2 Customizing `hl7_pdf_dcm.py`

Typical changes:

- **Directory locations:**  
  If you don’t want to anchor under `/var/lib/filemonitor/HL7toDICOM`, update:

```python
base_dir = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
hl7_dir  = "/your/path/HL7/"
pdf_dir  = "/your/path/PDFs/"
jpeg_dir = "/your/path/JPEGs/"
dcm_dir  = "/your/path/DICOM/"
error_dir = "/your/path/pdf2dcmERROR/"
```

- **HL7 mapping:**  
  Different sites may use:
  - PID‑18 instead of PID‑3,
  - PID‑8 instead of OBX‑11,
  - custom OBX for PDF.

Update the regexes in `parse_hl7` and the validation list in `process_hl7_file` accordingly. The pattern:

```python
re.search(r"(?:\|[^|]*){N}\|([^|]*)", line)
```

lets you change which field index you capture by adjusting `N`.

- **DICOM tags:**
  - Adjust `img2dcm` `-k` overrides if you want, for example, to:
    - set `StudyDescription` or `SeriesDescription`,
    - map a site code to `(0008,0080)` `InstitutionName`.

### 4.3 Customizing `ORU2pdf.py`

Common touchpoints:

- **Input/Output directories:**

```python
directory = "/var/lib/filemonitor/FAX"
pdf_dir   = "/var/lib/filemonitor/FAX/pdf"
json_dir  = "/var/lib/filemonitor/FAX/json"
```

Change these if your integration engine drops files somewhere else, or if you want environment‑specific trees (e.g. `/data/radrelay/fax/...`).

- **JSON keys used for naming:**

```python
fax_key = "Fax"
accn_key = "Accession"
```

If your JSON uses different keys (e.g. `DestinationFax`, `AccessionNumber`), update them.

Example change:

```python
fax_key = "DestinationFax"
accn_key = "AccessionNumber"
```

- **Logo and PDF layout:**
  - Update the hard‑coded logo path: `/opt/radx-workflow/photos/radxsulogo.png`.
  - Customize the `document` structure passed to `pdfme` (fonts, margins, titles, etc.) to match your branded layout.

### 4.4 Customizing `prelimSR.py` – Intelerad vs Non‑Intelerad

`prelimSR.py` is intentionally **opinionated** for Intelerad multi‑site environments:

- It **requires** the JSON `Facility` key:
  - For validating input.
  - For setting `ds.InstitutionName` in the DICOM SR.
  - For naming output files (`<Facility>_<Accession>.dcm`).
- It calls `findscu` with:

```python
"-k", f"0008,0050={accession}{facility}"
```

which mirrors a common Intelerad pattern where the PACS Accession Number is the concatenation of Accession + Facility/site code.

#### 4.4.1 Single‑facility environment (no facility routing)

If you have **one facility only**, and the PACS does not care about a facility code:

1. **Make `Facility` optional:**

```python
facility = json_data.get("Facility")
if not accession:
    log.error("JSON does not contain 'Accession' key.")
    sys.exit(1)

# Single facility: assign a default if Facility is missing
if not facility:
    facility = "MAIN"  # or any site label you want
```

2. **Change the `findscu` query to Accession only:**

In `query_study_uid`:

```python
acc_with_facility = f"{accession}{facility}"
```

can be simplified to:

```python
acc_with_facility = accession
```

3. **File naming and InstitutionName:**
   - If you don’t care about `<Facility>_` in filenames, change:

```python
output_filename = f"{facility}_{accession}.dcm"
```

to:

```python
output_filename = f"{accession}.dcm"
```

   - And optionally set `InstitutionName` to a constant:

```python
ds.InstitutionName = "MyHospital"
```

instead of reading it from JSON.

#### 4.4.2 Non‑Intelerad environment with different site encoding

If your PACS/RIS uses a **different** mechanism for multi‑site routing:

- Example 1: Accession is already unique without facility suffix  
  → treat as the single‑facility case above (Accession‑only `findscu`).

- Example 2: Site code is separate and you want to map `Facility` to a DICOM tag other than `InstitutionName`:

  - Keep `Facility` in the JSON, but point it elsewhere, e.g.:

```python
ds.InstitutionName = "MyVendorNeutralName"
ds.StationName = json_data.get("Facility", "")
```

  - Or use a lookup:

```python
site_map = {
    "CLINIC_A": "PACS_A",
    "CLINIC_B": "PACS_B",
}
site_code = json_data.get("Facility", "")
ds.InstitutionName = site_map.get(site_code, "DEFAULT_PACS")
```

- Example 3: You don’t have a `Facility` concept at all  
  → remove `Facility` from the mandatory checks, remove it from filenames, and drop it from the `findscu` query entirely.

#### 4.4.3 Adapting filename‑based AET routing

In `filemonitor.sh`, the Prelim DICOM monitor assumes:

- Filenames look like `AETprefix_something.dcm`, and
- `AETprefix` is a valid AE Title to use in `storescu`.

If your environment has:

- A single destination AE → set a constant `AET` as shown above.  
- A mapping from facility code to AE Title:

```bash
FACILITY="${BASENAME%%_*}"
case "$FACILITY" in
  FAC1) AET="INTELERAD_FAC1" ;;
  FAC2) AET="INTELERAD_FAC2" ;;
  *)    AET="DEFAULT_PACS"   ;;
esac
```

and keep the rest of the logic unchanged.

---

## 5. Using the Stack as a Temporary or Permanent Relay

Because each component is fairly self‑contained and paths/hosts are configured via top‑of‑file constants, this stack works well as:

- A **temporary bridge** during migrations:
  - Feed HL7/ORU/JSON from an older RIS/engine.
  - Produce DICOM objects and PDFs for a new PACS, or for side‑by‑side validation.
- A **permanent relay**:
  - Handle vendors that can only send PDFs or HL7 with embedded PDFs.
  - Generate SRs for systems that don’t natively support prelim workflows.
  - Drop PDFs to shared folders, send faxes, or email reports via additional tooling.

To adapt to a new site, you generally only need to:

1. Update **paths** in `filemonitor.sh` and the Python scripts.
2. Adjust **DICOM networking parameters** (`DICOM_HOST`, AE Titles, ports).
3. Adjust **HL7/JSON field mappings** in `hl7_pdf_dcm.py`, `prelimSR.py`, and `ORU2pdf.py`.
4. Optionally change **filename conventions** so downstream rules or routing tables are easy to define.

Because logging is isolated per script and the main log is compact, it’s straightforward to troubleshoot or tune the behavior in production without drowning in noise.
