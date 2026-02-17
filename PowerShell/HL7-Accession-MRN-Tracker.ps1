# Input/Output Folders 
$inputFolder = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\CRH 2022 Priors\Intelerad Updates"
$outputFile = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\duplicatesACCMRN2022.txt"

# Field counts storage
$fieldCounts = @{
    "OBR-2" = @{}
    "OBR-3" = @{}
    "ORC-2" = @{}
    "ORC-3" = @{}
}

# Track all accession occurrences with their MRNs
# Structure: $accessionOccurrences[Accession] = @(@{MRN="...", Count=1}, ...)
$accessionOccurrences = @{}

# Track which files each accession appears in
# Structure: $accessionFiles[Accession] = @{FileName1=count, FileName2=count, ...}
$accessionFiles = @{}

# Track simple count of each accession (to find duplicates)
$accessionCounts = @{}

# Track lines to remove: $linesToRemove[FilePath] = @(lineNumber1, lineNumber2, ...)
$linesToRemove = @{}

# Track duplicate accessions (accessions that appear more than 4 times)
$duplicateAccessions = @{}

# Track which lines contain which accessions: $lineAccessions[FilePath][LineNumber] = @(accession1, accession2, ...)
$lineAccessions = @{}

### NEW: Track message structure for each file
# $messageLines[filePath][messageId] = @(lineNumbers in that MSH block)
$messageLines = @{}
# $lineMessageIds[filePath][lineNumber] = messageId
$lineMessageIds = @{}
### END NEW

function Update-FieldCount {
    param(
        [hashtable]$counts,
        [string]$fieldKey,
        [string]$value
    )

    $normalizedValue = if ([string]::IsNullOrWhiteSpace($value)) { "<empty>" } else { $value }
    if ($counts[$fieldKey].ContainsKey($normalizedValue)) {
        $counts[$fieldKey][$normalizedValue]++
    } else {
        $counts[$fieldKey][$normalizedValue] = 1
    }
}

function Get-Hl7FieldValue {
    param(
        [string[]]$fields,
        [int]$index
    )

    if ($fields.Length -gt $index) {
        return $fields[$index].Trim()
    }

    return ""
}

function Process-Hl7File {
    param(
        [string]$filePath,
        [string]$fileName
    )
    
    # Track the current MRN as we process the file
    $currentMRN = ""
    
    # Initialize line tracking for this file
    if (-not $lineAccessions.ContainsKey($filePath)) {
        $lineAccessions[$filePath] = @{}
    }

    ### NEW: init message tracking for this file
    if (-not $messageLines.ContainsKey($filePath)) {
        $messageLines[$filePath] = @{}
    }
    if (-not $lineMessageIds.ContainsKey($filePath)) {
        $lineMessageIds[$filePath] = @{}
    }
    $currentMessageIndex = 0
    ### END NEW
    
    $lineNumber = 0
    
    # Read the input file line by line (each line is an HL7 segment)
    Get-Content $filePath | ForEach-Object {
        $lineNumber++
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        
        # First 3 characters determine the segment type
        if ($line.Length -lt 3) { return }
        $segmentType = $line.Substring(0, 3)

        ### NEW: Assign line to an MSH "message" block
        if ($segmentType -eq "MSH") {
            # New message starts
            $currentMessageIndex++
        }

        # If somehow we saw a non-MSH segment before first MSH, treat it as part of message 1
        if ($currentMessageIndex -eq 0) {
            $currentMessageIndex = 1
        }

        # Ensure containers exist for this message index
        if (-not $messageLines[$filePath].ContainsKey($currentMessageIndex)) {
            $messageLines[$filePath][$currentMessageIndex] = @()
        }
        $messageLines[$filePath][$currentMessageIndex] += $lineNumber
        $lineMessageIds[$filePath][$lineNumber] = $currentMessageIndex
        ### END NEW
        
        # Split fields by | delimiter only
        $fields = $line -split "\|"

        switch ($segmentType) {
            "PID" {
                # Get MRN from PID-2 or PID-3 (whichever is not empty)
                # PID-2 is at index 2, PID-3 is at index 3
                $pid2 = Get-Hl7FieldValue -fields $fields -index 2
                $pid3 = Get-Hl7FieldValue -fields $fields -index 3
                
                # Use PID-2 if not empty, otherwise use PID-3
                if (-not [string]::IsNullOrWhiteSpace($pid2)) {
                    $currentMRN = $pid2
                } elseif (-not [string]::IsNullOrWhiteSpace($pid3)) {
                    $currentMRN = $pid3
                } else {
                    $currentMRN = ""
                }
            }
            "ORC" {
                # ORC-2 is at index 2, ORC-3 is at index 3
                $currentORC2 = Get-Hl7FieldValue -fields $fields -index 2
                $currentORC3 = Get-Hl7FieldValue -fields $fields -index 3
                
                # Count the fields
                Update-FieldCount -counts $fieldCounts -fieldKey "ORC-2" -value $currentORC2
                Update-FieldCount -counts $fieldCounts -fieldKey "ORC-3" -value $currentORC3
                
                # Track accession occurrences (even if MRN is empty)
                $mrnToUse = if ([string]::IsNullOrWhiteSpace($currentMRN)) { "<no MRN>" } else { $currentMRN }
                
                # Track ORC-2 (accession)
                if (-not [string]::IsNullOrWhiteSpace($currentORC2)) {
                    # Count this accession
                    if ($accessionCounts.ContainsKey($currentORC2)) {
                        $accessionCounts[$currentORC2]++
                    } else {
                        $accessionCounts[$currentORC2] = 1
                    }
                    
                    # Track MRN association
                    if (-not $accessionOccurrences.ContainsKey($currentORC2)) {
                        $accessionOccurrences[$currentORC2] = @{}
                    }
                    if (-not $accessionOccurrences[$currentORC2].ContainsKey($mrnToUse)) {
                        $accessionOccurrences[$currentORC2][$mrnToUse] = 0
                    }
                    $accessionOccurrences[$currentORC2][$mrnToUse]++
                    
                    # Track file name
                    if (-not $accessionFiles.ContainsKey($currentORC2)) {
                        $accessionFiles[$currentORC2] = @{}
                    }
                    if (-not $accessionFiles[$currentORC2].ContainsKey($fileName)) {
                        $accessionFiles[$currentORC2][$fileName] = 0
                    }
                    $accessionFiles[$currentORC2][$fileName]++
                    
                    # Track line number for this accession
                    if (-not $lineAccessions[$filePath].ContainsKey($lineNumber)) {
                        $lineAccessions[$filePath][$lineNumber] = @()
                    }
                    $lineAccessions[$filePath][$lineNumber] += $currentORC2
                }
                
                # Track ORC-3 (accession)
                if (-not [string]::IsNullOrWhiteSpace($currentORC3)) {
                    # Count this accession
                    if ($accessionCounts.ContainsKey($currentORC3)) {
                        $accessionCounts[$currentORC3]++
                    } else {
                        $accessionCounts[$currentORC3] = 1
                    }
                    
                    # Track MRN association
                    if (-not $accessionOccurrences.ContainsKey($currentORC3)) {
                        $accessionOccurrences[$currentORC3] = @{}
                    }
                    if (-not $accessionOccurrences[$currentORC3].ContainsKey($mrnToUse)) {
                        $accessionOccurrences[$currentORC3][$mrnToUse] = 0
                    }
                    $accessionOccurrences[$currentORC3][$mrnToUse]++
                    
                    # Track file name
                    if (-not $accessionFiles.ContainsKey($currentORC3)) {
                        $accessionFiles[$currentORC3] = @{}
                    }
                    if (-not $accessionFiles[$currentORC3].ContainsKey($fileName)) {
                        $accessionFiles[$currentORC3][$fileName] = 0
                    }
                    $accessionFiles[$currentORC3][$fileName]++
                    
                    # Track line number for this accession
                    if (-not $lineAccessions[$filePath].ContainsKey($lineNumber)) {
                        $lineAccessions[$filePath][$lineNumber] = @()
                    }
                    $lineAccessions[$filePath][$lineNumber] += $currentORC3
                }
            }
            "OBR" {
                $obr2 = Get-Hl7FieldValue -fields $fields -index 2
                $obr3 = Get-Hl7FieldValue -fields $fields -index 3
                
                # Count the fields
                Update-FieldCount -counts $fieldCounts -fieldKey "OBR-2" -value $obr2
                Update-FieldCount -counts $fieldCounts -fieldKey "OBR-3" -value $obr3
                
                # Track accession occurrences (even if MRN is empty)
                $mrnToUse = if ([string]::IsNullOrWhiteSpace($currentMRN)) { "<no MRN>" } else { $currentMRN }
                
                # Track OBR-2 (accession)
                if (-not [string]::IsNullOrWhiteSpace($obr2)) {
                    # Count this accession
                    if ($accessionCounts.ContainsKey($obr2)) {
                        $accessionCounts[$obr2]++
                    } else {
                        $accessionCounts[$obr2] = 1
                    }
                    
                    # Track MRN association
                    if (-not $accessionOccurrences.ContainsKey($obr2)) {
                        $accessionOccurrences[$obr2] = @{}
                    }
                    if (-not $accessionOccurrences[$obr2].ContainsKey($mrnToUse)) {
                        $accessionOccurrences[$obr2][$mrnToUse] = 0
                    }
                    $accessionOccurrences[$obr2][$mrnToUse]++
                    
                    # Track file name
                    if (-not $accessionFiles.ContainsKey($obr2)) {
                        $accessionFiles[$obr2] = @{}
                    }
                    if (-not $accessionFiles[$obr2].ContainsKey($fileName)) {
                        $accessionFiles[$obr2][$fileName] = 0
                    }
                    $accessionFiles[$obr2][$fileName]++
                    
                    # Track line number for this accession
                    if (-not $lineAccessions[$filePath].ContainsKey($lineNumber)) {
                        $lineAccessions[$filePath][$lineNumber] = @()
                    }
                    $lineAccessions[$filePath][$lineNumber] += $obr2
                }
                
                # Track OBR-3 (accession)
                if (-not [string]::IsNullOrWhiteSpace($obr3)) {
                    # Count this accession
                    if ($accessionCounts.ContainsKey($obr3)) {
                        $accessionCounts[$obr3]++
                    } else {
                        $accessionCounts[$obr3] = 1
                    }
                    
                    # Track MRN association
                    if (-not $accessionOccurrences.ContainsKey($obr3)) {
                        $accessionOccurrences[$obr3] = @{}
                    }
                    if (-not $accessionOccurrences[$obr3].ContainsKey($mrnToUse)) {
                        $accessionOccurrences[$obr3][$mrnToUse] = 0
                    }
                    $accessionOccurrences[$obr3][$mrnToUse]++
                    
                    # Track file name
                    if (-not $accessionFiles.ContainsKey($obr3)) {
                        $accessionFiles[$obr3] = @{}
                    }
                    if (-not $accessionFiles[$obr3].ContainsKey($fileName)) {
                        $accessionFiles[$obr3][$fileName] = 0
                    }
                    $accessionFiles[$obr3][$fileName]++
                    
                    # Track line number for this accession
                    if (-not $lineAccessions[$filePath].ContainsKey($lineNumber)) {
                        $lineAccessions[$filePath][$lineNumber] = @()
                    }
                    $lineAccessions[$filePath][$lineNumber] += $obr3
                }
            }
        }
    }
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

foreach ($file in $inputFiles) {
    try {
        Write-Output "Processing: $($file.Name)..."
        Process-Hl7File -filePath $file.FullName -fileName $file.Name
        $processedCount++
        Write-Output "  ✓ Completed"
        Write-Output ""
    }
    catch {
        $errorCount++
        Write-Output "  ✗ Error processing $($file.Name): $($_.Exception.Message)"
        Write-Output ""
    }
}

Write-Output "File processing complete!"
Write-Output "  Successfully processed: $processedCount file(s)"
if ($errorCount -gt 0) {
    Write-Output "  Errors: $errorCount file(s)"
}
Write-Output ""

# Find duplicate accessions (accessions that appear more than 4 times)
$duplicates = @()

foreach ($accession in $accessionCounts.Keys) {
    $count = $accessionCounts[$accession]
    
    # If accession appears more than 4 times, record it as a duplicate
    if ($count -gt 4) {
        $duplicateAccessions[$accession] = $true
        
        # Get MRN information for this accession
        $mrnInfo = @()
        if ($accessionOccurrences.ContainsKey($accession)) {
            foreach ($mrn in $accessionOccurrences[$accession].Keys) {
                $mrnCount = $accessionOccurrences[$accession][$mrn]
                if ($mrn -eq "<no MRN>") {
                    $mrnInfo += "No MRN ($mrnCount time(s))"
                } else {
                    $mrnInfo += "$mrn ($mrnCount time(s))"
                }
            }
        }
        
        # Get file information for this accession
        $fileInfo = @()
        if ($accessionFiles.ContainsKey($accession)) {
            foreach ($file in $accessionFiles[$accession].Keys) {
                $fileCount = $accessionFiles[$accession][$file]
                $fileInfo += "$file ($fileCount time(s))"
            }
        }
        
        $mrnInfoList = if ($mrnInfo.Count -gt 0) { " - MRNs: " + ($mrnInfo -join ", ") } else { "" }
        $fileInfoList = if ($fileInfo.Count -gt 0) { " - Files: " + ($fileInfo -join ", ") } else { "" }
        $duplicates += "Duplicate Accession: $accession (appears $count time(s))$mrnInfoList$fileInfoList"
    }
}

# Mark lines for removal that contain duplicate accessions
foreach ($filePath in $lineAccessions.Keys) {
    if (-not $linesToRemove.ContainsKey($filePath)) {
        $linesToRemove[$filePath] = @()
    }
    
    foreach ($lineNumber in $lineAccessions[$filePath].Keys) {
        $accessionsOnLine = $lineAccessions[$filePath][$lineNumber]
        foreach ($acc in $accessionsOnLine) {
            if ($duplicateAccessions.ContainsKey($acc)) {
                ### NEW: remove the entire MSH block (message) containing this line
                $messageId = $null
                if ($lineMessageIds.ContainsKey($filePath) -and $lineMessageIds[$filePath].ContainsKey($lineNumber)) {
                    $messageId = $lineMessageIds[$filePath][$lineNumber]
                }

                if ($messageId -ne $null -and
                    $messageLines.ContainsKey($filePath) -and
                    $messageLines[$filePath].ContainsKey($messageId)) {

                    foreach ($msgLine in $messageLines[$filePath][$messageId]) {
                        if ($linesToRemove[$filePath] -notcontains $msgLine) {
                            $linesToRemove[$filePath] += $msgLine
                        }
                    }
                } else {
                    # Fallback: at least remove the current line
                    if ($linesToRemove[$filePath] -notcontains $lineNumber) {
                        $linesToRemove[$filePath] += $lineNumber
                    }
                }
                ### END NEW

                break  # Only need to process this line once
            }
        }
    }
}

# Function to remove lines from a file
function Remove-LinesFromFile {
    param(
        [string]$filePath,
        [int[]]$lineNumbersToRemove
    )
    
    if ($lineNumbersToRemove.Count -eq 0) {
        return
    }
    
    # Sort line numbers in descending order to remove from bottom to top
    $sortedLines = $lineNumbersToRemove | Sort-Object -Descending
    
    # Read all lines
    $allLines = Get-Content $filePath
    
    # Remove lines (working from bottom to top to preserve line numbers)
    foreach ($lineNum in $sortedLines) {
        if ($lineNum -le $allLines.Count) {
            $allLines = $allLines[0..($lineNum - 2)] + $allLines[$lineNum..($allLines.Count - 1)]
        }
    }
    
    # Write back to file
    $allLines | Out-File -FilePath $filePath -Encoding ASCII -Force
}

# Remove duplicate lines from files
Write-Output "Removing duplicate lines from files..."
$removedCount = 0
foreach ($filePath in $linesToRemove.Keys) {
    $linesToRemoveFromFile = $linesToRemove[$filePath] | Sort-Object
    if ($linesToRemoveFromFile.Count -gt 0) {
        try {
            Remove-LinesFromFile -filePath $filePath -lineNumbersToRemove $linesToRemoveFromFile
            Write-Output "  Removed $($linesToRemoveFromFile.Count) line(s) from: $(Split-Path $filePath -Leaf)"
            $removedCount += $linesToRemoveFromFile.Count
        }
        catch {
            Write-Output "  ✗ Error removing lines from $(Split-Path $filePath -Leaf): $($_.Exception.Message)"
        }
    }
}
Write-Output ""

# Output counts (only show counts > 1 on terminal)
Write-Output "Field Counts (showing only counts > 1):"
Write-Output ""
$hasCounts = $false
foreach ($fieldKey in ($fieldCounts.Keys | Sort-Object)) {
    foreach ($valueEntry in ($fieldCounts[$fieldKey].GetEnumerator() | Sort-Object -Property Name)) {
        if ($valueEntry.Value -gt 1) {
            $displayValue = if ($valueEntry.Name -eq "<empty>") { "<empty>" } else { $valueEntry.Name }
            Write-Output ("{0}: {1}, Count: {2}" -f $fieldKey, $displayValue, $valueEntry.Value)
            $hasCounts = $true
        }
    }
}

if (-not $hasCounts) {
    Write-Output "No counts greater than 1 found."
}

Write-Output ""
Write-Output "Ran check on folder: $inputFolder"
Write-Output ""

# Export duplicates to file
if ($duplicates.Count -gt 0) {
    Write-Output "Found $($duplicates.Count) duplicate(s). Exporting to $outputFile..."
    $duplicates | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Output "Duplicates exported to $outputFile"
} else {
    Write-Output "No duplicates found."
    # Create empty file or write message
    "No duplicates found." | Out-File -FilePath $outputFile -Encoding UTF8
}