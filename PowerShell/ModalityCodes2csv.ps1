# The script reads an HL7 flat file line by line, extracts the modality (usually OBR-24) field, and counts the occurrences of each modality code.

$inputFile = "path/to/hl7/flatfile.txt"
$outputFile = "path/to/facility/code/countsfile.csv"
# Hashtable for counts
$obr24Counts = @{}

# Read the input file line by line
Get-Content $inputFile | ForEach-Object {
    # Segment splitter
    $segments = $_ -split "\r"

    # Segment iteration to find OBR-24
    foreach ($segment in $segments) {
        if ($segment -like "OBR*") {
            # Split the OBR segment into fields
            $fields = $segment -split "\|"

            # Extract the OBR-24 field
            $obr24 = $fields[24]

            # Update the count for the OBR-24 value
            if ($obr24Counts.ContainsKey($obr24)) {
                $obr24Counts[$obr24]++
            } else {
                $obr24Counts[$obr24] = 1
            }
        }
    }
}

# Convert hashtable, export to CSV
$result = $obr24Counts.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        OBR24 = $_.Key
        Count = $_.Value
    }
}

# Export results CSV file
$result | Export-Csv -Path $outputFile -NoTypeInformation
Write-Output "Ran check on $inputFile."
Write-Output "OBR-24 counts have been saved to $outputFile"