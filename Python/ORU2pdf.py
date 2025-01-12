# This script is used to convert ORU messages structured as json files into pdf files. Please see the sampleORU text files in the "Text Files" folder for an example of the ORU message structure. The orignal text files were produced using Corepoint Integration Engine and forwarded to an interface connected the server hosting this script.
# 1. The script will convert the ORU messages into json files and then into pdf files. 
# 2. The pdf files will be renamed based on the fax number and accession number found in the json files, however this can be changed by modifying the "fax_key" and "accn_key" variables in the script.
# 3. The script will also add a logo to the pdf files and can also be customized by modifying the "image" key in the "document" dictionary under the "create_pdf_from_json" function.
# Errors will be printed to the console if the script encounters any issues with the files.
# Known bug: If there is more than one file to be converted, it will convert one correctly and move it to pdf_dir but for the files that follow, it will detect a pdf already converted and not rename the other files according to the logic and keep the original file names. **** This is a bug that needs to be fixed ****
# Requirements: pdfme library, chardet library, pillow library (for .jpeg images)
# For pdfme library documentation, please visit: https://pdfme.readthedocs.io/en/latest/

import json
import os
from pdfme import build_pdf
import glob
import chardet
import re
import time
check_mark = "\u2713"

def process_json_data(json_data):
    processed_lines = []
    for key, value in json_data.items():
        if isinstance(value, dict):
            for nested_key, nested_value in value.items():
                if isinstance(nested_value, str):
                    nested_value = nested_value.replace("\n\n", "\n \n")
                processed_lines.append(f"{key} -> {nested_key}: {nested_value}")
        else:
            if isinstance(value, str):
                value = value.replace("\n\n", "\n \n")
            processed_lines.append(f"{key}: {value}")

    return "\n".join(processed_lines)

def create_pdf_from_json(json_data, filename, pdf_dir):
    document = {
        "style": {
            "margin_bottom": 15, "text_align": "j",
            "page_size": "letter", "margin": [60, 50]
        },
        "formats": {
            "url": {"c": "blue", "u": 1},
            "title": {"b": 1, "s": 13}
        },
        "running_sections": {
            "footer": {
                "x": "left", "y": 740, "height": "bottom", "style": {"text_align": "c"},
                "content": [{".": ["Page ", {"var": "$page"}]}]
            }
        },
        "sections": [
            {
                "style": {"page_numbering_style": "roman"},
                "running_sections": ["footer"],
                "content": [
                    {"image": "path/to/image/logo.png"},
                    json_data
                ],
            }
        ]
    }

    output_filename = os.path.join(pdf_dir, os.path.splitext(filename)[0] + ".pdf")

    with open(output_filename, 'wb') as f:
        build_pdf(document, f)

def read_json_data(directory, pdf_dir, json_dir):
    for filename in glob.glob(f"{directory}/*.json"):
        try:
            with open(filename, 'rb') as file:
                result = chardet.detect(file.read())
                encoding = result['encoding']

            with open(filename, 'r', encoding=encoding) as file:
                json_data = json.load(file)

            processed_content = process_json_data(json_data)

            create_pdf_from_json(processed_content, os.path.basename(filename), pdf_dir)

            new_filename = os.path.join(json_dir, os.path.basename(filename))
            os.rename(filename, new_filename)

        except FileNotFoundError:
            print(f"Error: File not found - {filename}")
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON data in {filename}: {e}")

def rename_pdfs_with_json_key(pdf_dir, json_dir, fax_key, accn_key):
    for filename in os.listdir(pdf_dir):
        if not filename.endswith(".pdf"):
            continue

        pdf_path = os.path.join(pdf_dir, filename)
        json_path = os.path.join(json_dir, f"{os.path.splitext(filename)[0]}.json")

        if rename_pdf_with_json_key(pdf_path, json_path, fax_key, accn_key):
            print(f"-------------")
            time.sleep(.5)
        else:
            print(f"Error renaming PDF: {filename}")

def rename_pdf_with_json_key(pdf_path, json_path, fax_key, accn_key):
    filename, _ = os.path.splitext(os.path.basename(pdf_path))
    json_path = os.path.join(json_dir, f"{filename}.json")

    try:
        with open(json_path, 'rb') as f:
            result = chardet.detect(f.read())
            encoding = result['encoding']

        with open(json_path, 'r', encoding=encoding) as f:
            json_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON data in {json_path}: {e}")
        return False

    try:
        fax_value = json_data[fax_key]
        new_fax_value = json_data[fax_key].replace("-", "")
        accn_value = json_data[accn_key]
        new_name = f"fax={{1{new_fax_value}}}ACCN-{accn_value}"
    except KeyError:
        print(f"Warning: Key(s) '{fax_key}' or '{accn_key}' not found in JSON data. Using original filename.")
        new_name = os.path.splitext(filename)[0]

    new_pdf_path = os.path.join(os.path.dirname(pdf_path), f"{new_name}.pdf")

    try:
        os.rename(pdf_path, new_pdf_path)
        print(f"PDF renamed successfully: {filename} --> {new_name} {check_mark}")
        return True
    except OSError as e:
        print(f"Error renaming PDF: {e}")
        return False

def convert_txt_to_json(directory):
    for txt_filename in glob.glob(os.path.join(directory, "*.txt")):
        json_filename = os.path.splitext(txt_filename)[0] + ".json"
        os.rename(txt_filename, json_filename)
        print(f"Converted {txt_filename} --> {json_filename} {check_mark}")
        print(f"-------------")
        time.sleep(.5)

directory = "path/to/directory"
pdf_dir = "path/to/directory"
os.makedirs(pdf_dir, exist_ok=True)
json_dir = "path/to/directory"
os.makedirs(json_dir, exist_ok=True)
fax_key = "Fax"
accn_key = "Accession"

convert_txt_to_json(directory)
time.sleep(1)
read_json_data(directory, pdf_dir, json_dir)
rename_pdfs_with_json_key(pdf_dir, json_dir, fax_key, accn_key)