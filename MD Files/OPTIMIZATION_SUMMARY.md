# Optimization Summary: filemonitor.sh and hl7_pdf_dcm.py

## Issues Found and Fixed

### ✅ Fixed Issues

1. **Directory Mismatch** - Python script now accepts file path as argument, eliminating directory dependency
2. **Double Monitoring** - Removed polling loop from Python script; now event-driven via bash script
3. **Processing All Files** - Python script now processes only the file passed as argument
4. **Missing Error Handling** - Added error checks for `dcmdjpeg` before `storescu` calls
5. **File Completion** - Added `wait_for_file_complete()` function to ensure files are fully written
6. **Unused Import** - Removed unused `PIL.Image` import
7. **Variable Scope** - Fixed error handler to properly handle early exceptions
8. **Inefficient Scanning** - Eliminated directory scanning loop entirely

## New Files Created

### 1. `hl7_pdf_dcm_optimized.py`
- **Changes:**
  - Accepts file path as command-line argument
  - Removed `monitor_directory()` polling loop
  - Added `wait_for_file_complete()` function
  - Improved error handling with proper variable initialization
  - Removed unused `PIL.Image` import
  - Better error messages and validation

- **Usage:**
  ```bash
  python3 hl7_pdf_dcm_optimized.py /path/to/hl7_file
  ```

### 2. `filemonitor_optimized.sh`
- **Changes:**
  - Passes file path to Python script as argument
  - Added `wait_for_file_complete()` function
  - Added error checking for `dcmdjpeg` before `storescu`
  - Added skip for DICOM directory in main monitor loop
  - Better error handling throughout
  - Detects if Python script accepts file argument (backward compatible)

- **Usage:**
  ```bash
  ./filemonitor_optimized.sh
  ```

## Migration Guide

### Option 1: Use Optimized Versions (Recommended)

1. **Update Python Script:**
   ```bash
   cp Scripts/Python/hl7_pdf_dcm_optimized.py /RealRad/.hl7_pdf_dcm.py
   ```

2. **Update Bash Script:**
   ```bash
   cp Scripts/BASH/filemonitor_optimized.sh /path/to/filemonitor.sh
   chmod +x /path/to/filemonitor.sh
   ```

3. **Update Path in Bash Script:**
   - Edit `EXECUTE_SCRIPT` variable to point to your Python script location

### Option 2: Manual Fixes to Original Files

#### For `hl7_pdf_dcm.py`:
1. Change `input_dir = "/TargetDIR"` to `input_dir = "/RealRad"` (line 20)
2. Remove `monitor_directory()` function (lines 139-161)
3. Modify `if __name__ == "__main__":` block to accept file argument:
   ```python
   if __name__ == "__main__":
       import sys
       if len(sys.argv) < 2:
           logging.error("Usage: python3 hl7_pdf_dcm.py <hl7_file_path>")
           sys.exit(1)
       process_hl7_file(sys.argv[1])
   ```
4. Remove unused import: `from PIL import Image` (line 9)
5. Initialize variables at start of `process_hl7_file()` for error handling

#### For `filemonitor.sh`:
1. Change line 74 to pass file path:
   ```bash
   /usr/bin/python3.10 -u "$EXECUTE_SCRIPT" "$NEW_FILE" 2>> "$LOG_FILE" | tee -a "$LOG_FILE"
   ```
2. Add error checking for `dcmdjpeg` (around line 88):
   ```bash
   if dcmdjpeg "$NEW_DICOM_FILE" "$UNCOMPRESSED_FILE" 2>> "$LOG_FILE"; then
       # existing storescu code
   else
       log_message "BASH_ERR" "Failed to uncompress DICOM file"
       mv "$NEW_DICOM_FILE" "$DICOM_DIR/Failed/"
   fi
   ```

## Performance Improvements

- **Eliminated polling**: No more `while True` loop scanning directory
- **Event-driven**: Only processes files when detected by inotifywait
- **Single file processing**: Each file processed exactly once
- **Reduced CPU usage**: No continuous directory scanning
- **Better error recovery**: Files moved to Failed directory on errors

## Testing Recommendations

1. **Test with single file:**
   ```bash
   python3 hl7_pdf_dcm_optimized.py /RealRad/test_hl7_file
   ```

2. **Test file completion wait:**
   - Create a large file and verify it waits for completion

3. **Test error handling:**
   - Test with invalid HL7 files
   - Test with missing DICOM tools
   - Test with network failures

4. **Monitor logs:**
   - Check `/RealRad/ReportsMonitor.log` for any issues

## Backward Compatibility

The optimized bash script includes backward compatibility:
- Detects if Python script accepts file argument
- Falls back to old behavior if script doesn't accept arguments
- This allows gradual migration

## Notes

- The optimized Python script uses relative paths for output directories
- Adjust paths in Python script if needed for your environment
- DICOM configuration (host, port, AET) is now in variables at top of bash script
- File completion wait has 30-second timeout (adjustable)

