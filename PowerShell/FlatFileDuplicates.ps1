# ====== Config ======
# Input flat file (pipe-delimited)
$inputFile  = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\ScreenConnect\Files\CodyHistorical.OB_BillingFile_File_ADT_ORU.txt"

# Output file for duplicates
$outputFile = "C:\Users\GGuaracha\OneDrive - Casper Medical Imaging\Documents\ScreenConnect\Files\flatfileDuplicates.txt"

# ====== Sanity checks ======
if (-not (Test-Path $inputFile)) {
    Write-Error "Input file not found: $inputFile"
    exit 1
}

Write-Output "Reading flat file: $inputFile"
Write-Output ""

# ====== Data structures ======
# Count of each accession
$accessionCounts = @{}

# Lines per accession:
# $accessionLines[Accession] = @(@{ LineNumber = N; Line = "..." }, ...)
$accessionLines = @{}

# ====== First pass: read file and collect counts ======
$lineNumber = 0

Get-Content $inputFile | ForEach-Object {
    $lineNumber++
    $line = $_

    # Skip blank lines
    if ([string]::IsNullOrWhiteSpace($line)) { return }

    # Split by pipe
    $fields = $line -split '\|'

    # Need at least 2 fields for accession in field 2 (index 1)
    if ($fields.Count -lt 2) {
        Write-Output "Skipping line $lineNumber (not enough fields): $line"
        return
    }

    $accession = $fields[1].Trim()

    # If accession is empty, ignore this line (optional; change if you want to track them)
    if ([string]::IsNullOrWhiteSpace($accession)) {
        Write-Output "Skipping line $lineNumber (empty accession): $line"
        return
    }

    # Count this accession
    if (-not $accessionCounts.ContainsKey($accession)) {
        $accessionCounts[$accession] = 0
    }
    $accessionCounts[$accession]++

    # Track the line for this accession
    if (-not $accessionLines.ContainsKey($accession)) {
        $accessionLines[$accession] = @()
    }
    $accessionLines[$accession] += [pscustomobject]@{
        LineNumber = $lineNumber
        Line       = $line
    }
}

Write-Output ""
Write-Output "Finished scanning file. Total lines processed: $lineNumber"
Write-Output ""

# ====== Find duplicates ======
$duplicateAccessions = $accessionCounts.GetEnumerator() |
    Where-Object { $_.Value -gt 1 } |
    Sort-Object Name

if (-not $duplicateAccessions -or $duplicateAccessions.Count -eq 0) {
    Write-Output "No duplicate accession numbers found."

    "No duplicate accession numbers found in file:`n$inputFile" |
        Out-File -FilePath $outputFile -Encoding UTF8

    Write-Output "Wrote message to $outputFile"
    exit 0
}

# ====== Log duplicates to console ======
Write-Output "Duplicate accession numbers found:"
Write-Output ""

foreach ($entry in $duplicateAccessions) {
    $acc = $entry.Name
    $cnt = $entry.Value
    Write-Output ("  Accession {0} appears {1} time(s)" -f $acc, $cnt)
}

Write-Output ""
Write-Output ("Total distinct duplicate accessions: {0}" -f $duplicateAccessions.Count)
Write-Output ""

# ====== Write details to output file ======
$out = @()
$out += "Duplicate ORU reports in flat file"
$out += "Input file : $inputFile"
$out += "Generated  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$out += ""
$out += "Each line below is a report (line in the input file) whose accession appears more than once."
$out += ""

foreach ($entry in $duplicateAccessions) {
    $acc = $entry.Name
    $cnt = $entry.Value

    $out += ("Accession: {0} (appears {1} time(s))" -f $acc, $cnt)

    foreach ($info in $accessionLines[$acc]) {
        $out += ("  Line {0}: {1}" -f $info.LineNumber, $info.Line)
    }

    $out += ""  # blank line between accessions
}

$out | Out-File -FilePath $outputFile -Encoding UTF8

Write-Output ("Wrote duplicate details to: {0}" -f $outputFile)
