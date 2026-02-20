# Radiology

Scripts and utilities for radiology IT workflows: HL7 message handling, DICOM operations, and integration with PACS and RIS.

---

## Overview

This repository provides automation and tooling for radiology IT environments. The scripts support:

- **HL7** — Parsing, transforming, and routing ORU/ORU-R01 messages; converting embedded content to PDF and DICOM
- **DICOM** — Receiving studies (SCP), modifying tags, and sending to PACS
- **RIS/PACS integration** — Preliminary report workflows, modality code normalization, and report distribution (fax, email, network shares)

Scripts are intended to be adapted to local site requirements. They are maintained as needed for fixes and updates and are offered without commercial support.

---

## Repository Structure

| Directory | Description |
|-----------|-------------|
| **Python/** | Python scripts for HL7 parsing, PDF/DICOM conversion, modality updates, and structured report generation |
| **BASH/** | Shell scripts for file monitoring, DICOM SCP, batch file operations, and DICOM tag editing |
| **PowerShell/** | Windows scripts for HL7 flat-file analysis, modality reporting, field updates, and XML report handling |
| **Text Files/** | Sample HL7/ORU messages for testing (`sampleORU1.txt`–`sampleORU4.txt`, `sampleHL7FlatFile.txt`) |
| **MD Files/** | Analysis and optimization notes (e.g., file monitor and HL7 pipeline design) |

---

## Python Scripts

| Script | Purpose |
|--------|--------|
| `hl7_pdf_dcm.py` | Converts HL7 with base64 PDF in OBX-5 → PDF → JPEG → DICOM. For prelim reports when RIS cannot accept nighthawk prelim format. See `hl7_pdf_dcm.md` for customization. |
| `ORU2pdf.py` | Converts ORU messages (JSON) to PDF with optional logo; supports fax-oriented naming (e.g., by fax number and accession). |
| `Pipe2json.py` | Converts pipe-delimited HL7 flat files into JSON (configurable block size). |
| `ModalityCodeMod.py` | Rewrites OBR-24 (or configurable segment/field) in HL7 flat files via a replacement dictionary. |
| `OBR24Update.py` | Batch OBR-24 updates for all `.txt` files in the current directory using a replacement dictionary. |
| `prelimSR.py` | Builds Basic Text SR–style DICOM from JSON ORU; supports findscu and C-STORE for PACS. |
| `pmtconverter.py` | PMT (format) conversion utility. |
| `removeORUbydate.py` | Filters/removes ORU messages by date. |

---

## BASH Scripts

| Script | Purpose |
|--------|--------|
| `filemonitor_optimized.sh` | Event-driven monitor (e.g., inotify) for HL7/PDF/DICOM directories; invokes `hl7_pdf_dcm.py`, `ORU2pdf.py`, and optional DICOM send. |
| `filemonitor.sh` | Directory polling variant for HL7, fax, and DICOM workflows. |
| `scplistener.sh` | DICOM Storage SCP (storescp): listen for C-STORE and write received objects to a directory. |
| `dcmtags.sh` | Interactive DICOM tag insert/modify using dcmodify. |
| `fileEXTchange.sh` | Menu-driven batch extension change (e.g., JSON ↔ TXT) in a directory. |
| `AppendAllFiles.sh` | Concatenates all files in a directory into one output file. |

---

## PowerShell Scripts

| Script | Purpose |
|--------|--------|
| `HL7-Accession-MRN-Tracker.ps1` | Tracks accession/MRN across HL7 flat files; finds duplicates and supports line removal. |
| `HL7-Field-Counter.ps1` | Counts HL7 segment/field usage in flat files. |
| `HL7-Field-Updater.ps1` | Updates HL7 fields (e.g., gender mapping) across files in a folder. |
| `ModalityCodes2cli.ps1` | Extracts modality (e.g., OBR-24) from HL7 flat file and prints counts to console. |
| `ModalityCodes2csv.ps1` | Same as above; exports modality counts to CSV. |
| `FlatFileDuplicates.ps1` | Finds duplicate accessions in a pipe-delimited flat file; logs and optionally exports details. |
| `FilePattern.ps1` | File pattern / naming utilities. |
| `xmlreportsv2.ps1` | Processes a master XML report file; copies/splits into output directory structure. |

---

## Getting Started

### Clone the repository

```bash
git clone https://github.com/RadXSuperUser/Radiology.git
cd Radiology
```

**Windows (PowerShell):**

```powershell
cd C:\path\to\your\workspace
git clone https://github.com/RadXSuperUser/Radiology.git
cd Radiology
```

### Run a script

- **Python:** Ensure Python 3 and required packages (e.g., `pdf2image`, `pydicom`, `pdfme`) are installed. Run from the `Python` directory or set paths as required by the script.

  ```bash
  cd Python
  python hl7_pdf_dcm.py /path/to/file.hl7
  ```

- **BASH:** Use on a system with bash and any required tools (e.g., DCMTK, inotify-tools). Make scripts executable and adjust paths/variables inside the script.

  ```bash
  chmod +x BASH/filemonitor_optimized.sh
  ./BASH/filemonitor_optimized.sh
  ```

- **PowerShell:** Run in PowerShell; edit paths and parameters at the top of the script as needed.

  ```powershell
  .\PowerShell\ModalityCodes2csv.ps1
  ```

Each script has its own configuration (paths, AETs, ports, dictionaries). Customize and test in a non-production environment before deployment.

---

## Requirements (representative)

- **Python scripts:** Python 3.x; see script headers or `hl7_pdf_dcm.md` for libraries (e.g., `pdf2image`, Poppler, DCMTK `img2dcm`).
- **BASH scripts:** Bash, DCMTK (e.g., `storescp`, `dcmodify`, `img2dcm`), optionally `inotifywait`.
- **PowerShell scripts:** Windows PowerShell; no extra modules required unless noted in the script.

---

## Documentation

- **`Python/hl7_pdf_dcm.md`** — Description of the HL7→PDF→DICOM pipeline, HL7 segment mapping, and customization guide with examples.
- **`MD Files/`** — Project notes and optimization summaries (e.g., file monitor and HL7 processing).

---

## Contributing

Contributions are welcome. Please open an issue for bugs or feature requests and submit improvements via pull requests. By contributing, you agree that your contributions may be licensed under the same terms as the repository.

---

## License

This project is offered under the **MIT License** and **GNU License**. See the `MIT LICENSE` and `GNU LICENSE` files in the repository for full terms.

---

## Disclaimer

These scripts are provided **as-is** without warranty. Use at your own risk. The maintainers are not responsible for any damage or data loss resulting from their use. Always validate behavior and test in a safe environment before using with production systems or PHI.
