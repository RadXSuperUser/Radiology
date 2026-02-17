# Define the input and output folders
$inputFolder = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\CRH 2024 ORU"
$outputFolder = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\CRH 2024 ORU\Intelerad Updates - CRH 2024"

# Ensure output folder exists
if (-not (Test-Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    Write-Output "Created output folder: $outputFolder"
}

# Gender conversion mapping
$genderReplacements = @{
    "Female" = "F"
    "Male" = "M"
    "F" = "F"
    "M" = "M"
}

function Get-Hl7FieldValue {
    param(
        [string[]]$fields,
        [int]$index
    )

    if ($fields.Length -gt $index) {
        return $fields[$index]
    }

    return ""
}

function Set-Hl7FieldValue {
    param(
        [string[]]$fields,
        [int]$index,
        [string]$value
    )

    # Convert to ArrayList for easier manipulation
    $list = [System.Collections.ArrayList]::new($fields)
    
    # Ensure list is large enough by adding empty strings
    while ($list.Count -le $index) {
        [void]$list.Add("")
    }
    
    # Set the value at the specified index
    $list[$index] = $value
    
    return $list.ToArray()
}

function Update-Segment {
    param(
        [string]$line
    )

    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return $line }
    
    # First 3 characters determine the segment type
    if ($line.Length -lt 3) { return $line }
    $segmentType = $line.Substring(0, 3)
    
    # Split fields by | delimiter only
    $fields = $line -split "\|"

    switch ($segmentType) {
        "MSH" {
            # MSH-3/4/5/6 = Corepoint|CRH|Intelerad|CMI
            $fields = Set-Hl7FieldValue -fields $fields -index 2 -value "Corepoint"
            $fields = Set-Hl7FieldValue -fields $fields -index 3 -value "CRH"
            $fields = Set-Hl7FieldValue -fields $fields -index 4 -value "Intelerad"
            $fields = Set-Hl7FieldValue -fields $fields -index 5 -value "CMI"
        }
        "PID" {
            # PID-8 = Convert gender to single letter (F for female, M for male)
            $pid8 = Get-Hl7FieldValue -fields $fields -index 8
            if (-not [string]::IsNullOrWhiteSpace($pid8)) {
                $pid8Trimmed = $pid8.Trim()
                # Check if it's in the replacement mapping
                if ($genderReplacements.ContainsKey($pid8Trimmed)) {
                    $fields = Set-Hl7FieldValue -fields $fields -index 8 -value $genderReplacements[$pid8Trimmed]
                } else {
                    # Try case-insensitive pattern matching for "Female" or "Male"
                    $pid8Upper = $pid8Trimmed.ToUpper()
                    if ($pid8Upper -like "*FEMALE*") {
                        $fields = Set-Hl7FieldValue -fields $fields -index 8 -value "F"
                    } elseif ($pid8Upper -like "*MALE*" -and $pid8Upper -notlike "*FEMALE*") {
                        $fields = Set-Hl7FieldValue -fields $fields -index 8 -value "M"
                    }
                }
            }
        }
        "ORC" {
            # ORC-5 = ZZ (using same index as counter script)
            $fields = Set-Hl7FieldValue -fields $fields -index 5 -value "ZZ"
            # ORC-17 = CRH (using same index as counter script)
            $fields = Set-Hl7FieldValue -fields $fields -index 17 -value "CRH"
        }
        "OBR" {
            # OBR-8 = Copy OBR-14 data
            $obr14 = Get-Hl7FieldValue -fields $fields -index 14
            if (-not [string]::IsNullOrWhiteSpace($obr14)) {
                $fields = Set-Hl7FieldValue -fields $fields -index 8 -value $obr14
            }
            
            # OBR-6 = Copy OBR-7 data
            $obr7 = Get-Hl7FieldValue -fields $fields -index 7
            if (-not [string]::IsNullOrWhiteSpace($obr7)) {
                $fields = Set-Hl7FieldValue -fields $fields -index 6 -value $obr7
            }
            
            # OBR-18 = Copy OBR-2 data (using same index as counter script)
            $obr2 = Get-Hl7FieldValue -fields $fields -index 2
            if (-not [string]::IsNullOrWhiteSpace($obr2)) {
                $fields = Set-Hl7FieldValue -fields $fields -index 18 -value $obr2
            }
        }
    }

    # Reconstruct the line with | delimiter
    return $fields -join "|"
}

# Process all files in the input folder
$inputFiles = Get-ChildItem -Path $inputFolder -File

if ($inputFiles.Count -eq 0) {
    Write-Output "No files found in input folder: $inputFolder"
    exit
}

Write-Output "Found $($inputFiles.Count) file(s) to process..."
Write-Output ""

$processedCount = 0
$errorCount = 0

foreach ($inputFile in $inputFiles) {
    try {
        $inputFilePath = $inputFile.FullName
        $outputFilePath = Join-Path $outputFolder $inputFile.Name
        
        Write-Output "Processing: $($inputFile.Name)..."
        
        # Read the input file, process each line, and write to output
        $outputLines = @()

        Get-Content $inputFilePath | ForEach-Object {
            $updatedLine = Update-Segment -line $_
            $outputLines += $updatedLine
        }

        # Write all processed lines to the output file
        $outputLines | Out-File -FilePath $outputFilePath -Force -Encoding ASCII
        
        $processedCount++
        Write-Output "  ✓ Saved to: $outputFilePath"
        Write-Output ""
    }
    catch {
        $errorCount++
        Write-Output "  ✗ Error processing $($inputFile.Name): $($_.Exception.Message)"
        Write-Output ""
    }
}

Write-Output "Processing complete!"
Write-Output "  Successfully processed: $processedCount file(s)"
if ($errorCount -gt 0) {
    Write-Output "  Errors: $errorCount file(s)"
}
