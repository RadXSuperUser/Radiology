# Input/Output Files
$inputFile = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\Change PACS\Cody\CRH 2022 Priors\Intelerad Updates\CRH Priors 2022 1.OB_Change PACS_ADT_ORM_ORU.txt"

# Field counts storage
$fieldCounts = @{
    "MSH-3" = @{}
    "MSH-4" = @{}
    "MSH-5" = @{}
    "MSH-6" = @{}
    "ORC-5" = @{}
    "ORC-17" = @{}
    "OBR-18" = @{}
}

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

# Track the most recent MSH and ORC values seen while iterating through the file
$currentMshFields = @{
    "MSH-3" = ""
    "MSH-4" = ""
    "MSH-5" = ""
    "MSH-6" = ""
}

$currentOrcFields = @{
    "ORC-5" = ""
    "ORC-17" = ""
}

# Read the input file line by line (each line is an HL7 segment)
Get-Content $inputFile | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    
    # First 3 characters determine the segment type
    if ($line.Length -lt 3) { return }
    $segmentType = $line.Substring(0, 3)
    
    # Split fields by | delimiter only
    $fields = $line -split "\|"

    switch ($segmentType) {
        "MSH" {
            $currentMshFields["MSH-3"] = Get-Hl7FieldValue -fields $fields -index 2
            $currentMshFields["MSH-4"] = Get-Hl7FieldValue -fields $fields -index 3
            $currentMshFields["MSH-5"] = Get-Hl7FieldValue -fields $fields -index 4
            $currentMshFields["MSH-6"] = Get-Hl7FieldValue -fields $fields -index 5

            foreach ($fieldKey in $currentMshFields.Keys) {
                Update-FieldCount -counts $fieldCounts -fieldKey $fieldKey -value $currentMshFields[$fieldKey]
            }
        }
        "ORC" {
            $currentOrcFields["ORC-5"] = Get-Hl7FieldValue -fields $fields -index 5
            $currentOrcFields["ORC-17"] = Get-Hl7FieldValue -fields $fields -index 17

            foreach ($fieldKey in $currentOrcFields.Keys) {
                Update-FieldCount -counts $fieldCounts -fieldKey $fieldKey -value $currentOrcFields[$fieldKey]
            }
        }
        "OBR" {
            $obr2 = Get-Hl7FieldValue -fields $fields -index 2
            $obr18 = Get-Hl7FieldValue -fields $fields -index 18

            Update-FieldCount -counts $fieldCounts -fieldKey "OBR-18" -value $obr18

            $fieldsToCheck = @(
                @{ Name = "MSH-3"; Value = $currentMshFields["MSH-3"] },
                @{ Name = "MSH-4"; Value = $currentMshFields["MSH-4"] },
                @{ Name = "MSH-5"; Value = $currentMshFields["MSH-5"] },
                @{ Name = "MSH-6"; Value = $currentMshFields["MSH-6"] },
                @{ Name = "ORC-5"; Value = $currentOrcFields["ORC-5"] },
                @{ Name = "ORC-17"; Value = $currentOrcFields["ORC-17"] },
                @{ Name = "OBR-18"; Value = $obr18 }
            )

            foreach ($entry in $fieldsToCheck) {
                if ([string]::IsNullOrWhiteSpace($entry.Value)) {
                    Write-Output ("{0} empty: '{1}'" -f $entry.Name, $obr2)
                }
            }
        }
    }
}

# Output counts
foreach ($fieldKey in ($fieldCounts.Keys | Sort-Object)) {
    foreach ($valueEntry in ($fieldCounts[$fieldKey].GetEnumerator() | Sort-Object -Property Name)) {
        $displayValue = if ($valueEntry.Name -eq "<empty>") { "<empty>" } else { $valueEntry.Name }
        Write-Output ("{0}: {1}, Count: {2}" -f $fieldKey, $displayValue, $valueEntry.Value)
    }
}

Write-Output "Ran check on $inputFile."