"""
This script processes all ORU flat files saved as `.txt` in the current directory, specifically targeting lines that start with "OBR". It checks the 24th field (OBR-24) in these lines and replaces its value based on a predefined dictionary of replacements. The script writes the updated content to a temporary file to ensure safe in-place updates.

obr24_replacements: A dictionary containing OBR-24 replacements. The keys are the original OBR-24 values, and the values are the replacements. Can be modified to include additional replacements.
- Recommended to run the obr24countsV2.py script first to identify the current OBR-24 values in the flatfile. This will help identify which values to replace as not all PACS or different systems accept the same OBR-24 values, thus making the dictionary unique to each system.

Be sure to retain the original flat files or back them up before running this script to avoid data loss in case of errors.
"""
import os

# Define OBR-24 replacements
obr24_replacements = {
    "STEREOTACTIC": "MG",
    "TISSUE": "MG",
    "MAMMOGRAPHY": "MG",
    "DIGITAL": "MG",
    "DXA": "OT",
    "MRCP": "MR"
}

# Get the current directory
current_directory = os.getcwd()

# Get all .txt files in the directory
txt_files = [f for f in os.listdir(current_directory) if f.endswith(".txt")]

# Process each .txt file
for txt_file in txt_files:
    input_file = os.path.join(current_directory, txt_file)
    temp_file = input_file + ".tmp"  # Temporary file for safe in-place updates

    # Open the input file for reading and the temporary file for writing
    with open(input_file, "r", encoding="utf-8") as infile, open(temp_file, "w", encoding="utf-8") as outfile:
        for line in infile:
            stripped_line = line.rstrip("\r\n")  # Preserve original line endings
            updated_line = stripped_line

            # Check if the line starts with OBR
            if stripped_line.startswith("OBR"):
                fields = stripped_line.split("|")
                if len(fields) > 24:  # Ensure OBR-24 exists
                    obr24 = fields[24]
                    if obr24 in obr24_replacements:
                        # Replace the OBR-24 value
                        fields[24] = obr24_replacements[obr24]
                        updated_line = "|".join(fields)

            # Write the updated line to the temporary file
            outfile.write(updated_line + "\n")

    # Replace the original file with the temporary file
    os.replace(temp_file, input_file)

    print(f"Updated OBR-24 fields in file: {txt_file}")

print("All .txt files have been processed.")