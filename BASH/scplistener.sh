#!/bin/bash

# Description:
# This script runs a DICOM Storage Service Class Provider (SCP) listener using storescp.
# It listens on a specified port for incoming DICOM files and stores them in a designated
# output directory. This is commonly used to receive DICOM images from remote systems
# or DICOM senders.
#
# Usage: ./scplistener.sh
#
# The script uses the storescp utility from DCMTK (DICOM Toolkit) to:
# - Listen for incoming DICOM connections on a specified port
# - Accept DICOM files sent via C-STORE operations
# - Save received files to a specified output directory
#
# Configuration:
# Modify the variables below to customize the listener for your environment:
# - AE_TITLE: Application Entity Title (identifies this SCP to remote systems)
# - PORT: Network port number to listen on
# - OUTPUT_DIR: Directory where received DICOM files will be stored
# - PRELOAD_MODE: Set to true to enable preload mode (loads images into memory)

# Configuration variables - modify these to fit your use case
AE_TITLE="DOC_IMPORT"          # Application Entity Title
PORT="4000"                    # Port number to listen on
OUTPUT_DIR="/home/$USER/test"  # Directory to store received DICOM files
PRELOAD_MODE=true              # Enable preload mode (set to false to disable)
VERBOSE=true                   # Enable verbose output (set to false to disable)

# Build the storescp command
STORESCP_CMD="storescp"

# Add verbose flag if enabled
if [ "$VERBOSE" = true ]; then
    STORESCP_CMD="$STORESCP_CMD -v"
fi

# Add Application Entity Title
STORESCP_CMD="$STORESCP_CMD -aet $AE_TITLE"

# Add preload mode if enabled
if [ "$PRELOAD_MODE" = true ]; then
    STORESCP_CMD="$STORESCP_CMD -pm"
fi

# Add output directory
STORESCP_CMD="$STORESCP_CMD -od $OUTPUT_DIR"

# Add port number
STORESCP_CMD="$STORESCP_CMD +B $PORT"

# Check if output directory exists, create if it doesn't
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Output directory does not exist. Creating: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
fi

# Display configuration
echo "Starting DICOM SCP Listener..."
echo "AE Title: $AE_TITLE"
echo "Port: $PORT"
echo "Output Directory: $OUTPUT_DIR"
echo "Preload Mode: $PRELOAD_MODE"
echo "Verbose: $VERBOSE"
echo ""
echo "Press Ctrl+C to stop the listener"
echo ""

# Run storescp
$STORESCP_CMD
