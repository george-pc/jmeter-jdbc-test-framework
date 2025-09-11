#!/bin/bash

# Convert multi-line CSV queries to single-line format for JMeter compatibility
# Usage: ./convert_multiline_csv.sh input.csv output.csv

INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [ $# -ne 2 ]; then
    echo "Usage: $0 input.csv output.csv"
    echo "Example: $0 data_files/kantar_original_test_queries.csv data_files/kantar_singleline_queries.csv"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Input file not found: $INPUT_FILE"
    exit 1
fi

echo "🔄 Converting multi-line CSV to single-line format..."
echo "Input: $INPUT_FILE"
echo "Output: $OUTPUT_FILE"

# Use Python to properly handle CSV parsing and convert to single-line
python3 - "$INPUT_FILE" "$OUTPUT_FILE" << 'EOF'
import csv
import sys
import re

input_file = sys.argv[1]
output_file = sys.argv[2]

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
                
                # Clean up the query: remove extra whitespace, normalize line breaks
                query_cleaned = ' '.join(query_text.split())
                
                # Remove SQL comments (-- comments)
                query_cleaned = re.sub(r'--[^\n]*', '', query_cleaned)
                
                # Clean up extra spaces after comment removal
                query_cleaned = ' '.join(query_cleaned.split())
                
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