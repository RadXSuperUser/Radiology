import csv
import os
from datetime import datetime

def process_files(file_list, log_file, date_threshold):
    accession_nums_to_remove = set()
    
    for file_path in file_list:
        entries_to_keep = []
        with open(file_path, 'r') as f:
            reader = csv.DictReader(f, delimiter='|')
            for row in reader:
                begin_exam_dttm = row.get('BEGIN_EXAM_DTTM')
                accession_num = row.get('ACCESSION_NUM')
                
                # Parse the date and check if it's newer than the threshold
                if begin_exam_dttm and datetime.strptime(begin_exam_dttm, '%m/%d/%Y') >= date_threshold:
                    if accession_num:
                        accession_nums_to_remove.add(accession_num)
                else:
                    entries_to_keep.append(row)

        # Rewrite the file without the removed entries
        with open(file_path, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=reader.fieldnames, delimiter='|')
            writer.writeheader()
            writer.writerows(entries_to_keep)

    # Log the removed accession numbers
    with open(log_file, 'w') as log:
        for accession_num in accession_nums_to_remove:
            log.write(f"{accession_num}\n")

# Example usage
file_directory = 'data_files'  # Replace with the directory containing your files
file_list = [os.path.join(file_directory, filename) for filename in os.listdir(file_directory) if filename.endswith('.pipe')]
log_file = 'FAC_NT10012024_ORU_PRIORS.txt'
date_threshold = datetime.strptime('10/1/2024', '%m/%d/%Y')

process_files(file_list, log_file, date_threshold)
