#!/bin/bash

# Set the target directory (current directory by default)
DIR="C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\CRH 2022 Priors\Intelerad Updates"

# Set the output file name
OUTPUT="C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\CRH 2022 Priors\Intelerad Updates\CRH 2022 Master ORU.txt"

# Clear the output file if it already exists
> "$OUTPUT"

# Loop through all regular files (skip the output file itself)
for FILE in "$DIR"/*; do
    if [[ -f "$FILE" && "$FILE" != "$OUTPUT" ]]; then
        echo "Appending: $FILE"
        cat "$FILE" >> "$OUTPUT"
        echo -e "\n" >> "$OUTPUT"  # optional: adds a newline between files
    fi
done

echo "✅ All data appended to $OUTPUT"