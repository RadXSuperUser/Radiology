#!/usr/bin/env python3
"""
Convert a JSON-formatted ORU report into a Basic Text SR-like DICOM object.

Dependencies:
    pip install pydicom

Usage:
    python json_oru_to_basic_text_sr.py input_oru.json
"""

import json
import logging
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pydicom
from pydicom.dataset import Dataset, FileDataset
from pydicom.sequence import Sequence
from pydicom.uid import ExplicitVRLittleEndian, generate_uid

FIND_SCU_AET = "ORTHANC"
FIND_SCU_PEER = "192.168.1.15"
FIND_SCU_PORT = 4242
BASIC_TEXT_SR_SOP_CLASS_UID = "1.2.840.10008.5.1.4.1.1.88.11"
PRELIM_LOG_DIR = "/var/lib/filemonitor/PrelimSR/logs"
PRELIM_LOG_FILE = os.path.join(PRELIM_LOG_DIR, "prelimSR.log")
os.makedirs(PRELIM_LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.FileHandler(PRELIM_LOG_FILE, encoding="utf-8")],
)
log = logging.getLogger(__name__)


def parse_dicom_date(date_str):
    """Accept 'YYYYMMDD' or 'MM/DD/YYYY'; return 'YYYYMMDD' or None."""
    if not date_str:
        return None
    s = str(date_str).strip()
    if len(s) == 8 and s.isdigit():
        return s
    for fmt in ("%m/%d/%Y",):
        try:
            dt = datetime.strptime(s, fmt)
            return dt.strftime("%Y%m%d")
        except ValueError:
            continue
    return None


def parse_dicom_time(time_str):
    """
    Accept:
      - 'HHMMSS'
      - 'HHMM' / 'HMM'
      - 'YYYYMMDDHHMMSS' -> 'HHMMSS'
    Return valid TM or None.
    """
    if not time_str:
        return None
    s = str(time_str).strip()
    if len(s) >= 14 and s[:14].isdigit():
        return s[8:14]
    if 4 <= len(s) <= 6 and s.isdigit():
        return s
    return None


def split_signed_time(signed_str):
    """Take 'YYYYMMDDHHMMSS' -> (YYYYMMDD, HHMMSS) or (None, None)."""
    if not signed_str:
        return None, None
    s = str(signed_str).strip()
    if len(s) >= 14 and s[:14].isdigit():
        return s[:8], s[8:14]
    return None, None


def parse_datetime_mmddyyyy(date_time_str):
    """
    Accept 'MM/DD/YYYY H:MM:SS AM/PM' or 'MM/DD/YYYY HH:MM:SS'.
    Return (YYYYMMDD, HHMMSS) or (None, None).
    """
    if not date_time_str:
        return None, None
    s = str(date_time_str).strip()
    for fmt in ("%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt.strftime("%Y%m%d"), dt.strftime("%H%M%S")
        except ValueError:
            continue
    return None, None


def split_person_name(name):
    """
    Convert 'FIRST LAST' to 'LAST^FIRST' unless already in 'LAST^FIRST' form.
    """
    if not name:
        return ""
    s = str(name).strip()
    if "^" in s:
        return s
    parts = s.split()
    if len(parts) >= 2:
        first = " ".join(parts[:-1])
        last = parts[-1]
        return f"{last}^{first}"
    return s


def query_study_uid(accession, facility):
    """
    Use findscu to query PACS for StudyInstanceUID (0020,000D)
    based on AccessionNumber (0008,0050) = <accession><facility>.

    Returns the UID string if found, else None.
    """
    if not accession or not facility:
        log.warning("Cannot query PACS: missing accession or facility.")
        return None
    acc_with_facility = f"{accession}{facility}"
    cmd = [
        "findscu",
        "-v",
        "-S",
        "-k",
        "0008,0052=STUDY",
        "-k",
        f"0008,0050={acc_with_facility}",
        "-k",
        "0020,000D",
        "-aet",
        FIND_SCU_AET,
        FIND_SCU_PEER,
        str(FIND_SCU_PORT),
    ]
    connection_timeout_marker = "Association Request Failed"
    tcp_timeout_marker = "Connection timed out"
    log.info("Running findscu: %s", " ".join(cmd))
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    except Exception as e:
        log.warning("findscu failed to run: %s", e)
        return None
    output = result.stdout or ""
    if connection_timeout_marker in output and tcp_timeout_marker in output:
        log.info("PACS connection timed out; proceeding without StudyInstanceUID from findscu.")
        return None
    uid_pattern = re.compile(r"I:\s*\(0020,000d\)\s*UI\s*\[(.*?)\]")
    for line in output.splitlines():
        match = uid_pattern.search(line)
        if match:
            uid = match.group(1).strip()
            if uid:
                log.info("Found StudyInstanceUID via findscu: %s", uid)
                return uid
    log.warning("No StudyInstanceUID found in findscu output.")
    return None


def create_basic_text_sr_from_json(json_data, output_path):
    """Build and save an SR DICOM file from parsed JSON ORU data."""
    file_meta = Dataset()
    file_meta.MediaStorageSOPClassUID = BASIC_TEXT_SR_SOP_CLASS_UID
    sop_instance_uid = generate_uid()
    file_meta.MediaStorageSOPInstanceUID = sop_instance_uid
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
    file_meta.ImplementationClassUID = generate_uid()
    ds = FileDataset(
        output_path,
        {},
        file_meta=file_meta,
        preamble=b"\0" * 128,
    )
    ds.is_little_endian = True
    ds.is_implicit_VR = False
    now = datetime.now()
    now_date = now.strftime("%Y%m%d")
    now_time = now.strftime("%H%M%S")
    ds.InstanceCreationDate = now_date
    ds.InstanceCreationTime = now_time
    patient_name_raw = json_data.get("PatientName", "")
    ds.PatientName = split_person_name(patient_name_raw)
    mrn = json_data.get("MRN") or json_data.get("Mrn") or json_data.get("mrn")
    ds.PatientID = "" if mrn is None else str(mrn)
    dob_raw = json_data.get("DoB", "")
    dob_str = parse_dicom_date(dob_raw)
    ds.PatientBirthDate = dob_str if dob_str else ""
    sex = json_data.get("PatientSex") or json_data.get("Sex") or json_data.get("SEX")
    if sex:
        ds.PatientSex = str(sex)[0].upper()
    else:
        ds.PatientSex = ""
    study_date_raw = json_data.get("StudyDate") or json_data.get("Study Date")
    study_time_raw = json_data.get("StudyTime") or json_data.get("Study Time")
    study_date = parse_dicom_date(study_date_raw) if study_date_raw else None
    study_time = parse_dicom_time(study_time_raw) if study_time_raw else None
    signed = json_data.get("SignedTime")
    if signed and (not study_date or not study_time):
        sdate, stime = split_signed_time(signed)
        if not study_date:
            study_date = sdate
        if not study_time:
            study_time = stime
    if not study_date or not study_time:
        exam_time = json_data.get("ExamTime") or json_data.get("Contact")
        if exam_time:
            edate, etime = parse_datetime_mmddyyyy(exam_time)
            if not study_date:
                study_date = edate
            if not study_time:
                study_time = etime
    if not study_date:
        study_date = now_date
    if not study_time:
        study_time = now_time
    ds.StudyDate = study_date
    ds.StudyTime = study_time
    ds.ContentDate = study_date
    ds.ContentTime = study_time
    custom_suid = json_data.get("SUID")
    if custom_suid:
        ds.StudyInstanceUID = str(custom_suid)
        log.info("Using StudyInstanceUID from JSON SUID: %s", custom_suid)
    else:
        ds.StudyInstanceUID = generate_uid()
        log.info("No SUID in JSON; generated StudyInstanceUID: %s", ds.StudyInstanceUID)
    ds.SeriesInstanceUID = generate_uid()
    ds.StudyID = str(json_data.get("Accession", ""))
    ds.AccessionNumber = str(json_data.get("Accession", ""))
    ds.Modality = "SR"
    ds.SeriesNumber = "1"
    ds.InstanceNumber = "1"
    ds.StudyDescription = str(json_data.get("ExamType", ""))
    ds.SeriesDescription = "Preliminary Report"
    ds.InstitutionName = str(json_data.get("Facility", ""))
    ds.Manufacturer = "RadInformatix"
    ds.ReferringPhysicianName = split_person_name(json_data.get("Ordering", ""))
    ds.NameOfPhysiciansReadingStudy = split_person_name(json_data.get("Radiologist", ""))
    ds.SOPClassUID = BASIC_TEXT_SR_SOP_CLASS_UID
    ds.SOPInstanceUID = sop_instance_uid
    ds.CompletionFlag = "COMPLETE"
    ds.VerificationFlag = "UNVERIFIED"
    doc_title = Dataset()
    doc_title.CodeValue = "11528-7"
    doc_title.CodingSchemeDesignator = "LN"
    doc_title.CodeMeaning = "Radiology Report"
    ds.ConceptNameCodeSequence = Sequence([doc_title])
    ds.ValueType = "CONTAINER"
    ds.ContinuityOfContent = "SEPARATE"
    ppcs_item = Dataset()
    ppcs_item.CodeValue = "P0"
    ppcs_item.CodingSchemeDesignator = "99LOCAL"
    ppcs_item.CodeMeaning = str(json_data.get("ExamType", "Imaging procedure"))
    ds.PerformedProcedureCodeSequence = Sequence([ppcs_item])
    ds.ReferencedPerformedProcedureStepSequence = Sequence([])
    report_text = str(json_data.get("Report", ""))
    root = Dataset()
    root.RelationshipType = "CONTAINS"
    root.ValueType = "CONTAINER"
    findings_code = Dataset()
    findings_code.CodeValue = "121070"
    findings_code.CodingSchemeDesignator = "DCM"
    findings_code.CodeMeaning = "Findings"
    root.ConceptNameCodeSequence = Sequence([findings_code])
    root.ContinuityOfContent = "SEPARATE"
    text_item = Dataset()
    text_item.RelationshipType = "CONTAINS"
    text_item.ValueType = "TEXT"
    finding_code = Dataset()
    finding_code.CodeValue = "121071"
    finding_code.CodingSchemeDesignator = "DCM"
    finding_code.CodeMeaning = "Finding"
    text_item.ConceptNameCodeSequence = Sequence([finding_code])
    text_item.TextValue = report_text
    root.ContentSequence = Sequence([text_item])
    ds.ContentSequence = Sequence([root])
    log.debug("Root item: %s %s", ds.ContentSequence[0].RelationshipType, ds.ContentSequence[0].ValueType)
    ds.save_as(output_path, write_like_original=False)


def main():
    if len(sys.argv) != 2:
        log.error("Usage: prelimSR.py input_oru.json")
        sys.exit(1)
    input_path = Path(sys.argv[1])
    if not input_path.exists():
        log.error("Input file not found: %s", input_path)
        sys.exit(1)
    log.info("Processing: %s", input_path.name)
    with input_path.open("r", encoding="utf-8") as f:
        json_data = json.load(f)
    accession = json_data.get("Accession")
    facility = json_data.get("Facility")
    if not accession:
        log.error("JSON does not contain 'Accession' key.")
        sys.exit(1)
    if not facility:
        log.error("JSON does not contain 'Facility' key.")
        sys.exit(1)
    suid_from_pacs = query_study_uid(accession, facility)
    if suid_from_pacs:
        existing_suid = str(json_data.get("SUID", "") or "")
        if existing_suid:
            json_data["SUID"] = existing_suid + suid_from_pacs
        else:
            json_data["SUID"] = suid_from_pacs
        try:
            with input_path.open("w", encoding="utf-8") as jf:
                json.dump(json_data, jf)
            log.info("Updated JSON SUID with PACS StudyInstanceUID: %s", json_data["SUID"])
        except Exception as e:
            log.warning("Failed to write updated SUID back to JSON file: %s", e)
    else:
        log.info("Proceeding without SUID from PACS (SR will use generated StudyInstanceUID).")
    output_filename = f"{facility}_{accession}.dcm"
    output_path = input_path.parent / output_filename
    create_basic_text_sr_from_json(json_data, str(output_path))
    prelim_dir = Path("/var/lib/filemonitor/PrelimSR")
    dicom_dir = prelim_dir / "DICOM"
    json_dir = prelim_dir / "JSON"
    prelim_dir.mkdir(exist_ok=True)
    dicom_dir.mkdir(exist_ok=True)
    json_dir.mkdir(exist_ok=True)
    sr_dest = dicom_dir / output_filename
    try:
        shutil.move(str(output_path), sr_dest)
        log.info("Moved SR to: %s", sr_dest)
    except Exception as e:
        log.warning("Could not move SR file to %s: %s", sr_dest, e)
    json_dest = json_dir / input_path.name
    try:
        shutil.move(str(input_path), json_dest)
        log.info("Moved JSON to: %s", json_dest)
    except Exception as e:
        log.warning("Could not move JSON file to %s: %s", json_dest, e)
    try:
        rel_sr = sr_dest.relative_to(prelim_dir)
        rel_json = json_dest.relative_to(prelim_dir)
        log.info("Completed. SR: ./%s, JSON: ./%s", rel_sr, rel_json)
    except ValueError:
        log.info("Completed. SR: %s, JSON: %s", sr_dest, json_dest)


if __name__ == "__main__":
    main()

