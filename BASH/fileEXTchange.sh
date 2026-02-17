#!/bin/bash

# Description:
# This script provides an interactive menu-driven interface for batch renaming files
# by changing their extensions. It supports converting between different file extensions
# (e.g., JSON to TXT, TXT to JSON) in a specified directory.
#
# Usage: ./fileEXTchange.sh
#
# Features:
# - Convert JSON files to TXT files
# - Convert TXT files to JSON files
# - Specify target directory for file operations
# - Interactive menu for easy selection
#
# Instructions to add more extension conversion options:
# 1. Add a new function following the pattern of json_to_txt() or txt_to_json()
# 2. Add a new menu option in the display_menu() function
# 3. Add a corresponding case statement in the display_menu() function's case block
# 4. Update the description at the top of the file to document the new feature
#
# Example function template:
#   convert_ext1_to_ext2() {
#       read -p "Enter directory path: " dir
#       for file in "$dir"/*.ext1; do
#           mv -- "$file" "$dir/$(basename -- "$file" .ext1).ext2"
#       done
#   }

# Color codes
CYAN="\033[36m"
RED="\033[31m"
GREEN="\033[32m"
NORMAL="\033[0;39m"

# Convert JSON to TXT
json_to_txt() {
    read -p "Enter directory path (default: current directory): " dir
    dir=${dir:-.}
    
    if [ ! -d "$dir" ]; then
        printf $RED
        echo "Error: Directory '$dir' does not exist."
        printf $NORMAL
        return 1
    fi
    
    count=0
    for file in "$dir"/*.json; do
        if [ -f "$file" ]; then
            mv -- "$file" "$dir/$(basename -- "$file" .json).txt"
            ((count++))
        fi
    done
    
    printf $GREEN
    echo "Converted $count JSON file(s) to TXT in '$dir'"
    printf $NORMAL
}

# Convert TXT to JSON
txt_to_json() {
    read -p "Enter directory path (default: current directory): " dir
    dir=${dir:-.}
    
    if [ ! -d "$dir" ]; then
        printf $RED
        echo "Error: Directory '$dir' does not exist."
        printf $NORMAL
        return 1
    fi
    
    count=0
    for file in "$dir"/*.txt; do
        if [ -f "$file" ]; then
            mv -- "$file" "$dir/$(basename -- "$file" .txt).json"
            ((count++))
        fi
    done
    
    printf $GREEN
    echo "Converted $count TXT file(s) to JSON in '$dir'"
    printf $NORMAL
}

# Display menu
display_menu() {
    echo ""
    echo "=========================================="
    echo "File Extension Converter"
    echo "=========================================="
    echo "Choose an action:"
    echo "1. Convert JSON files to TXT"
    echo "2. Convert TXT files to JSON"
    echo "3. Exit"
    read -p "Enter your choice: " choice
    
    case $choice in
        1)
            json_to_txt
            ;;
        2)
            txt_to_json
            ;;
        3)
            printf $CYAN
            echo "Exiting..."
            printf $NORMAL
            exit 0
            ;;
        *)
            printf $RED
            echo "Invalid choice. Please try again."
            printf $NORMAL
            ;;
    esac
}

# Main loop
while true; do
    display_menu
done
