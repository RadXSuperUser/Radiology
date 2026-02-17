import pandas as pd

def update_fields(source_file, target_file, legacy_column, new_column, target_column, output_file):
    # Determine the file format and set the appropriate read and write functions
    if source_file.endswith('.xlsx'):
        read_source = lambda file: pd.read_excel(file, engine='openpyxl')
    elif source_file.endswith('.xls'):
        read_source = lambda file: pd.read_excel(file, engine='xlrd')
    elif source_file.endswith('.csv'):
        read_source = pd.read_csv
    else:
        raise ValueError(f"Unsupported file format: {source_file}")

    if target_file.endswith('.xlsx'):
        read_target = lambda file: pd.read_excel(file, engine='openpyxl')
        write_target = lambda df, file: df.to_excel(file, index=False, engine='openpyxl')
    elif target_file.endswith('.xls'):
        read_target = lambda file: pd.read_excel(file, engine='xlrd')
        write_target = lambda df, file: df.to_excel(file, index=False, engine='openpyxl')
    elif target_file.endswith('.csv'):
        read_target = pd.read_csv
        write_target = lambda df, file: df.to_csv(file, index=False)
    else:
        raise ValueError(f"Unsupported file format: {target_file}")

    # Read the files
    source_df = read_source(source_file)
    target_df = read_target(target_file)

    # Ensure the specified columns exist in the dataframes
    if legacy_column not in source_df.columns or new_column not in source_df.columns:
        raise ValueError(f"Columns '{legacy_column}' and/or '{new_column}' not found in source file.")
    if target_column not in target_df.columns:
        raise ValueError(f"Column '{target_column}' not found in target file.")

    # Create a dictionary from the source dataframe to map legacy values to new values
    update_dict = source_df.set_index(legacy_column)[new_column].to_dict()

    # Update the target dataframe
    target_df[target_column] = target_df[target_column].map(update_dict).fillna(target_df[target_column])

    # Save the updated dataframe to a new file
    write_target(target_df, output_file)
    print(f"Updated file saved as '{output_file}'")

# Usage example
source_file = 'source.xlsx'  # Can be 'source.xlsx', 'source.xls', or 'source.csv'
target_file = '/home/dynecs/BannerClinic_ChargeMaster.csv'  # Can be 'target.xlsx', 'target.xls', or 'target.csv'
legacy_column = 'Legacy Catalog CD'  # Column in the source file with legacy values
new_column = 'New Catalog CD'        # Column in the source file with new values
target_column = 'Procedure Code'  # Column in the target file to update data
output_file = '/home/dynecs/NewPMT.csv'  # Can be 'updated_target.xlsx', 'updated_target.xls', or 'updated_target.csv'

update_fields(source_file, target_file, legacy_column, new_column, target_column, output_file)