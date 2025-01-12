# This script reads a pipe-delimited HL7 flat file and converts it to multiple JSON files.
# Each JSON file contains a specified number of blocks from the pipe-delimited file. This is useful for processing large files in smaller chunks and can be easily modified to suit your needs by changing the delimiter, max_blcks variable, and output format.

import csv
import json

def pipe_delimited_to_json(pipe_delimited_file, base_json_file, max_blocks):
    entries = []
    current_entry = None
    block_counter = 0
    file_counter = 1

    def save_entries_to_file(entries, file_counter):
        file_name = f"{base_json_file}_{file_counter}.json"
        with open(file_name, 'w') as f:
            json.dump(entries, f, indent=4)
        print(f"Saved {len(entries)} entries to {file_name}")

    with open(pipe_delimited_file, 'r') as f:
        reader = csv.DictReader(f, delimiter='|')
        
        for row in reader:
            if current_entry is None or row['LINE'] == '1':
                # Save the current entry if it exists
                if current_entry:
                    entries.append(current_entry)
                    block_counter += 1

                # Start a new entry
                current_entry = {k: v for k, v in row.items() if k != 'NOTE_TEXT' and k != 'LINE'}
                current_entry['NOTE_TEXT'] = row['NOTE_TEXT']
                
                # Check if we need to save to a new file
                if block_counter == max_blocks:
                    save_entries_to_file(entries, file_counter)
                    entries = []
                    block_counter = 0
                    file_counter += 1
            else:
                # Aggregate the NOTE_TEXT for the current entry with a | at the start
                current_entry['NOTE_TEXT'] += " | " + row['NOTE_TEXT']
        
        # Save the last set of entries
        if current_entry:
            entries.append(current_entry)
        if entries:
            save_entries_to_file(entries, file_counter)

# Example usage
pipe_delimited_file = 'data.pipe'  # Replace with your pipe-delimited file path
base_json_file = 'data'  # Base name for your JSON files
max_blocks = 100  # Maximum number of blocks per file

pipe_delimited_to_json(pipe_delimited_file, base_json_file, max_blocks)