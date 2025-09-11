#!/bin/bash

# Convert multi-line CSV queries to single-line format for JMeter compatibility
# This version preserves comments by converting -- comments to /* */ block comments
# Usage: ./convert_multiline_csv_preserve_comments.sh input.csv output.csv

INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [ $# -ne 2 ]; then
    echo "Usage: $0 input.csv output.csv"
    echo "Example: $0 data_files/kantar_original_test_queries.csv data_files/kantar_singleline_with_comments.csv"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Input file not found: $INPUT_FILE"
    exit 1
fi

echo "🔄 Converting multi-line CSV to single-line format (preserving comments)..."
echo "Input: $INPUT_FILE"
echo "Output: $OUTPUT_FILE"

# Use Python to properly handle CSV parsing and convert to single-line
python3 - "$INPUT_FILE" "$OUTPUT_FILE" << 'EOF'
import csv
import sys
import re

input_file = sys.argv[1]
output_file = sys.argv[2]

def convert_line_comments_to_block(query):
    """Convert SQL line comments (--) to block comments (/* */)"""
    
    # Pattern to match -- comments
    # This regex finds -- followed by any characters until end of line
    # We need to be careful not to match -- inside strings
    
    lines = query.split('\n')
    result_lines = []
    
    for line in lines:
        # Simple approach: if line contains --, check if it's a comment
        # This is a basic implementation - a more robust one would handle strings
        if '--' in line:
            # Find the position of --
            comment_pos = line.find('--')
            
            # Check if it's not inside quotes (basic check)
            # Count quotes before the --
            quotes_before = line[:comment_pos].count("'") + line[:comment_pos].count('"')
            
            # If even number of quotes, likely not inside a string
            if quotes_before % 2 == 0:
                # Split at comment position
                before_comment = line[:comment_pos]
                comment_text = line[comment_pos+2:].strip()
                
                if comment_text:  # Only add block comment if there's actual comment text
                    line = f"{before_comment} /* {comment_text} */"
                else:
                    line = before_comment
        
        result_lines.append(line)
    
    return ' '.join(' '.join(line.split()) for line in result_lines if line.strip())

try:
    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', encoding='utf-8', newline='') as outfile:
        
        # Use csv.reader to properly parse quoted multi-line fields
        reader = csv.reader(infile)
        writer = csv.writer(outfile, quoting=csv.QUOTE_MINIMAL)
        
        for row_num, row in enumerate(reader):
            if row_num == 0:
                # Skip header row
                continue
                
            if len(row) >= 2:  # Ensure we have at least Query_Alias and Query columns
                query_alias = row[0]
                query_text = row[1]
                
                # Convert -- comments to /* */ block comments
                query_with_block_comments = convert_line_comments_to_block(query_text)
                
                # Clean up extra whitespace
                query_cleaned = ' '.join(query_with_block_comments.split())
                
                # Ensure query ends with semicolon (but don't add if already there)
                if not query_cleaned.strip().endswith(';'):
                    query_cleaned = query_cleaned.strip()
                else:
                    # Remove semicolon to add it back consistently
                    query_cleaned = query_cleaned.strip()[:-1]
                
                # Use numeric ID instead of Query_N
                numeric_id = row_num
                
                # Write row without semicolon (Databricks doesn't need it)
                writer.writerow([numeric_id, query_cleaned])
                
                print(f"✅ Row {numeric_id}: {len(query_cleaned)} chars")
            else:
                print(f"⚠️  Skipping row {row_num}: insufficient columns")
    
    print("✅ Conversion completed successfully!")
    
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)
    
EOF