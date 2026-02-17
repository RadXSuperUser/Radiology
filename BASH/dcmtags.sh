#!/bin/bash

# Description:
# This script provides an interactive menu-driven interface for modifying DICOM file tags.
# It allows users to insert new tags, modify existing tags, or insert tag values from files
# into a specified DICOM file using the dcmodify utility.
#
# Usage: ./dcmtags.sh <DICOM file>
#
# Features:
# - Insert a new DICOM tag with a specified value
# - Modify an existing DICOM tag with a new value
# - Insert a DICOM tag value from a file
# - Interactive menu that loops until the user chooses to exit

CYAN="\033[36m"
RED="\033[31m"
NORMAL="\033[0;39m"

# Insert
insert_tag() {
    read -p "Enter the tag (in the format (XXXX,XXXX)): " tag
    read -p "Enter the value: " value
    printf $CYAN
    dcmodify --insert "$tag=$value" --verbose "$1"
    printf $NORMAL
}

# Modify
modify_tag() {
    read -p "Enter the tag (in the format (XXXX,XXXX)): " tag
    read -p "Enter the value: " value
    printf $CYAN
    dcmodify --modify "$tag=$value" --verbose "$1"
    printf $NORMAL
}

# Insert from a file
insert_from_file() {
    read -p "Enter the tag (in the format (XXXX,XXXX)): " tag
    read -p "Enter the file location: " file
    printf $CYAN
    dcmodify --insert-from-file "$tag=$file" --verbose "$1"
    printf $NORMAL
}

# Menu
display_menu() {
    echo "Choose an action:"
    echo "1. Insert a tag"
    echo "2. Modify a tag"
    echo "3. Insert a tag from a file"
    echo "4. Exit"
    read -p "Enter your choice: " choice

    case $choice in
        1)
            insert_tag "$1"
            ;;
        2)
            modify_tag "$1"
            ;;
        3)
            insert_from_file "$1"
            ;;
        4)
            exit 0
            ;;
        *)
            printf $RED
            echo "Invalid choice. Please try again."
            printf $NORMAL
            ;;
    esac
}

# Check DICOM file is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <DICOM file>"
    exit 1
fi

# Main
while true; do
    display_menu "$1"
done