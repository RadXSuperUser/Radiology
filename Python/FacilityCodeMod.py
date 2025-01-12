# This script is used to modify the facility codes in a flat file of HL7 ORU's. The script will read the input file line by line and search for the OBR segment. If the OBR segment is found, the script will check the OBR-24 field for specific values and replace them with new values. The modified messages will be saved to an output file. The script uses a dictionary to define the replacements for OBR-24 values. The input and output file paths, as well as the replacements, can be customized as needed. The script also handles multiline messages and ensures that the modified messages are saved without extra spaces or lines.
# You can change what segment and field you want to modify by changing the "if line.startswith("OBR"):" condition and the "fields[24]" index in the script. You can also add/modify the "obr24_replacements" dictionary if needed.
# If you change the segment or field, make sure to update the logic accordingly to ensure that the script correctly identifies and replaces the values in the HL7 messages.

import re

# Define input and output files
input_file = "C:/path/to/hl7messages.txt"
output_file = "C:/path/to/filtered_hl7messages.txt"

# Define OBR-24 replacements
obr24_replacements = {
    "STEREOTACTIC": "MG",
    "TISSUE": "MG",
    "MAMMOGRAPHY": "MG",
    "DIGITAL": "MG",
    "DXA": "OT"
}

# Initialize variables
matching_messages = []
current_message = []
is_matching = False

# Read the input file line by line
with open(input_file, "r", encoding="utf-8") as infile:
    for line in infile:
        line = line.strip()

        # Check if the line starts with MSH (start of a new message)
        if line.startswith("MSH"):
            # If we were processing a matching message, save it to the list
            if is_matching and current_message:
                matching_messages.append("\r".join(current_message))

            # Reset for the new message
            current_message = []
            is_matching = False

        # Add the line to the current message
        current_message.append(line)

        # Check if the line starts with OBR
        if line.startswith("OBR"):
            fields = line.split("|")
            if len(fields) > 24:  # Ensure OBR-24 exists
                obr24 = fields[24]
                if obr24 in obr24_replacements:
                    # Replace the OBR-24 value
                    fields[24] = obr24_replacements[obr24]
                    # Update the OBR line in the current message
                    current_message[-1] = "|".join(fields)
                    # Mark the message as matching
                    is_matching = True

    # Add the last message if it was a match
    if is_matching and current_message:
        matching_messages.append("\r".join(current_message))

# Write all matching messages to the output file without adding extra spaces or lines
with open(output_file, "w", encoding="utf-8") as outfile:
    outfile.write("\r".join(matching_messages))

print(f"Filtered messages have been saved to {output_file}")