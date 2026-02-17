# Master XML file path
$masterXmlPath = "Path\To\Master\XML File"

# Master file name without extension
$masterFileName = [System.IO.Path]::GetFileNameWithoutExtension($masterXmlPath)

# Output directory to make folders for new files
$outputDirBase = "Path\To\Make\New\XML Files\Folders\$masterFileName"
$outputDir = $outputDirBase

# Create the initial output directory
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory
}

$masterXmlContent = Get-Content -Path $masterXmlPath -Raw
$counter = 1
$folderCounter = 1
$reportPattern = "(?s)<report>.*?</report>"
$xmlHeader = "<?xml version=`"1.0`" encoding=`"UTF-8`" standalone=`"yes`"?>`n<extract xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">"
$xmlFooter = "</extract>"

# Loop master XML file, delete reports as they are copied
while ($masterXmlContent -match $reportPattern) {
    
    $reportSection = [regex]::Match($masterXmlContent, $reportPattern).Value

    # Debug message: Check if a report section was found
    if ($reportSection) {
        Write-Host "Found report section, length: $($reportSection.Length)"
    } else {
        Write-Host "No report section found, exiting loop."
        break
    }

    # 10k counter check to make new folders
    if ($counter -gt 10000) {
        $folderCounter++
        $outputDir = "${outputDirBase}_${folderCounter}"
        
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory
        }
        $counter = 1
    }

    # New XML file copied section
    $fullXmlContent = "$xmlHeader`n$reportSection`n$xmlFooter"
    $newXmlFile = Join-Path -Path $outputDir -ChildPath ("report_" + $counter + ".xml")
    Set-Content -Path $newXmlFile -Value $fullXmlContent

    if (Test-Path $newXmlFile) {
        Write-Host "Created new XML file: $newXmlFile"
    } else {
        Write-Host "Failed to create XML file: $newXmlFile"
    }

    # Remove the copied section from the master XML
    $masterXmlContent = $masterXmlContent -replace [regex]::Escape($reportSection), ''

    $counter++
}

Set-Content -Path $masterXmlPath -Value $masterXmlContent

if ($masterXmlContent.Length -eq (Get-Content -Path $masterXmlPath -Raw).Length) {
    Write-Host "Master XML file was updated successfully."
} else {
    Write-Host "Failed to update master XML file."
}