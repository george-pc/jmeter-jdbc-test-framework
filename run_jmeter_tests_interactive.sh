#!/usr/bin/env bash

#Set the JAVA_HOME and JAVA version 17 because that is needed for the JSR script in Jmeter
export JAVA_HOME=/opt/homebrew/opt/openjdk@17

# Basic configuration
JMETER_HOME=$(pwd)
echo "JMETER_HOME is set to: $JMETER_HOME"

# Directory paths
TEST_PLAN_PATH="${JMETER_HOME}/Test-Plans"
TEST_PROPERTIES_PATH="${JMETER_HOME}/test_properties"
CONNECTION_PROPERTIES_PATH="${JMETER_HOME}/connection_properties"
QUERIES_PATH="${JMETER_HOME}/data_files"
REPORT_PATH="${JMETER_HOME}/reports"
METADATA_PATH="${JMETER_HOME}/metadata_files"

JMETER_BIN="${JMETER_HOME}/apache-jmeter-5.6.3/bin"

# Default files
DEFAULT_TEST_PLAN="Test-Plan-ArrivalsBased-with-Shuffle.jmx"
DEFAULT_TEST_PROPERTIES="sample_test.properties"
DEFAULT_CONNECTION_PROPERTIES="sample_connection.properties"
DEFAULT_QUERIES="sample_jmeter_queries.csv"
DEFAULT_METADATA="sample_metadata.txt"

# Function to display files
show_files() {
    local path="$1"
    local pattern="$2"
    local title="$3"
    
    echo ""
    echo "==========================================================="
    echo "$title - Please select from below :"
    echo "==========================================================="
    echo "Directory: $path"
    echo ""
    find "$path" -maxdepth 1 -type f -name "$pattern" -exec basename {} \; | sort
    echo ""
    echo "==========================================================="
}

# Function to get the filename as user input
get_filename() {
    local path="$1"
    local default="$2"
    local title="$3"
    
    # Send headers to stderr
    echo "" >&2
    #echo "================================================" >&2
    #echo " $title - SELECT FILE" >&2
    #echo "================================================" >&2
    
    while true; do
        read -p "Enter filename [$default]: " filename >&2
        [ -z "$filename" ] && filename="$default"

        if [ -f "$path/$filename" ]; then
            echo "Selected: $filename" >&2  # Status message to stderr
            echo "$filename"  # Only output the filename to stdout
            return 0
        else
            echo "Error: File not found. Please try again." >&2
        fi
    done
}

# Main execution
echo "Starting user input file selection..."

# Select  METADATA FILE
show_files "$METADATA_PATH" "*.txt" "METADATA FILE"
SELECTED_METADATA_FILE=$(get_filename "$METADATA_PATH" "$DEFAULT_METADATA" "METADATA FILE")
METADATA_FILE="${METADATA_PATH}/${SELECTED_METADATA_FILE}"
# update defaults and metadata from the selected metadata file
source "$METADATA_FILE"

# TEST PLAN
show_files "$TEST_PLAN_PATH" "*.jmx" "TEST PLAN"
SELECTED_TEST_PLAN=$(get_filename "$TEST_PLAN_PATH" "$DEFAULT_TEST_PLAN" "TEST PLAN")
TEST_PLAN="${TEST_PLAN_PATH}/${SELECTED_TEST_PLAN}"

# TEST PROPERTIES
show_files "$TEST_PROPERTIES_PATH" "*.properties" "TEST PROPERTIES"
SELECTED_TEST_PROPERTIES=$(get_filename "$TEST_PROPERTIES_PATH" "$DEFAULT_TEST_PROPERTIES" "TEST PROPERTIES")
TEST_PROPERTIES="${TEST_PROPERTIES_PATH}/${SELECTED_TEST_PROPERTIES}"

# CONNECTION PROPERTIES
show_files "$CONNECTION_PROPERTIES_PATH" "*.properties" "CONNECTION PROPERTIES"
SELECTED_CONNECTION_PROPERTIES=$(get_filename "$CONNECTION_PROPERTIES_PATH" "$DEFAULT_CONNECTION_PROPERTIES" "CONNECTION PROPERTIES")
CONNECTION_PROPERTIES="${CONNECTION_PROPERTIES_PATH}/${SELECTED_CONNECTION_PROPERTIES}"

# QUERIES FILE
show_files "$QUERIES_PATH" "*.csv" "QUERIES FILE"
SELECTED_QUERIES_FILE=$(get_filename "$QUERIES_PATH" "$DEFAULT_QUERIES" "QUERIES FILE")
QUERIES_FILE="${QUERIES_PATH}/${SELECTED_QUERIES_FILE}"


echo ""
echo "================================================"
echo " FINAL SELECTIONS"
echo "================================================"
echo "1. Test Plan: $TEST_PLAN"
echo "2. Test Properties: $TEST_PROPERTIES"
echo "3. Connection Properties: $CONNECTION_PROPERTIES"
echo "4. Queries File: $QUERIES_FILE"
echo "5. Metadata File: $METADATA_FILE"
echo "================================================"


# Get Jmeter hostname and OS info
JMETER_HOSTNAME=$(hostname)

#Get the run_id and run_date from the start time
START_TIME=$(date +%Y%m%d-%H%M%S)
RUN_ID="$START_TIME"
RUN_DATE="${START_TIME:0:8}"  # Extract the date part (first 8 characters)
echo "$START_TIME" > "$REPORT_PATH/start_time.txt"

# Get JDBC_URL from connection properties file
JDBC_URL=$(grep '^CONNECTION_STRING' "$CONNECTION_PROPERTIES" | awk -F'=' '{print $2}' | tr -d '[:space:]')

# Check if JDBC_URL is empty or invalid
if [[ -z "$JDBC_URL" ]]; then
  echo "ERROR: JDBC_URL not found in $CONNECTION_PROPERTIES"
  exit 1
fi

# Get cluster hostname from JDBC URL
CLUSTER_HOSTNAME=$(echo "$JDBC_URL" | awk -F'/' '{print $3}' | awk -F':' '{print $1}')

# Check if CLUSTER_HOSTNAME is empty or invalid
if [[ -z "$CLUSTER_HOSTNAME" ]]; then
  echo "ERROR: Unable to extract CLUSTER_HOSTNAME from JDBC_URL: $JDBC_URL"
  exit 1
fi


# Define result files
JMETER_RESULT_FILE="$REPORT_PATH/JmeterResultFile_${START_TIME}.csv"
AGGREGATE_REPORT="$REPORT_PATH/AggregateReport_${START_TIME}.csv"
SUMMARY_REPORT="$REPORT_PATH/SummaryReport_${START_TIME}.csv"
CONFIG_FILE="$REPORT_PATH/test_config_${START_TIME}.json"
TEST_RESULT_FILE="$REPORT_PATH/test_result_${START_TIME}.json"
STATISTICS_FILE="$REPORT_PATH/dashboard_${START_TIME}/statistics.json"
JMETER_LOG="$REPORT_PATH/jmeter_${START_TIME}.log"
CONSOLE_LOG="$REPORT_PATH/jmeter_console_${START_TIME}.log"


# Display the properties and start the test
echo "Starting JMeter test run at $START_TIME"
echo "Test Plan: $TEST_PLAN"
echo "Test Properties: $TEST_PROPERTIES"
echo "Connection Properties: $CONNECTION_PROPERTIES"
echo "JDBC_URL = $JDBC_URL"
echo "CLUSTER_HOSTNAME = $CLUSTER_HOSTNAME"
echo "Results will be saved to: $REPORT_PATH"

# Check if required files exist
for file in "$TEST_PLAN" "$TEST_PROPERTIES" "$CONNECTION_PROPERTIES"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: Missing required file: $file"
    exit 1
  fi
done


# Start the Jmeter run

"$JMETER_BIN/jmeter" -n -t "$TEST_PLAN"\
    -q "$TEST_PROPERTIES" \
    -q "$CONNECTION_PROPERTIES" \
    -JSTART_TIME="$START_TIME" \
    -JQUERY_PATH="$QUERIES_FILE" \
    -l "$JMETER_RESULT_FILE" \
    -e -o "$REPORT_PATH/dashboard_${START_TIME}" \
    -j "$JMETER_LOG" 2>&1 | tee "$CONSOLE_LOG"

# Extract final summary line
JMETER_RUN_SUMMARY=$(grep "summary =" "$CONSOLE_LOG" | tail -n 1)
if [[ -z "$JMETER_RUN_SUMMARY" ]]; then
  echo "ERROR: JMeter summary not found. Check logs for more information."
  exit 1
else
  echo "JMeter Summary: $JMETER_RUN_SUMMARY"
fi


#Get End time
END_TIME=$(date +%Y%m%d_%H%M%S)

# Calculate additional stats from Aggregate Report
if [[ -f "$AGGREGATE_REPORT" ]]; then
  echo "Extracting additional metrics from Aggregate Report..."
fi

# General basic Stats for config file
total_queries=$(awk -F',' 'NR>1 {count++} END {print count+0}' "$AGGREGATE_REPORT")
total_success=$(awk -F',' 'NR>1 && $4 ~ /200/ {count++} END {print count+0}' "$AGGREGATE_REPORT")
total_failed=$((total_queries - total_success))

# Prevent division by zero error
error_percent=$(awk 'BEGIN {if ('$total_queries' > 0) printf "%.2f", ('$total_failed'/'$total_queries')*100; else print "0.00"}')


# Response Times
min_time=$(awk -F',' 'NR>1 {print $2}' "$AGGREGATE_REPORT" | sort -n | head -1)
max_time=$(awk -F',' 'NR>1 {print $2}' "$AGGREGATE_REPORT" | sort -n | tail -1)
avg_time=$(awk -F',' 'NR>1 {sum+=$2; count++} END {if (count>0) printf "%.2f", sum/count; else print "0.00"}' "$AGGREGATE_REPORT")

# Ensure variables are safe for JSON generation
total_queries=${total_queries:-0}
total_success=${total_success:-0}
total_failed=${total_failed:-0}
error_percent=${error_percent:-"0.00"}
min_time=${min_time:-"0"}
max_time=${max_time:-"0"}
avg_time=${avg_time:-"0"}

# Generate JSON Summary
echo "Generating JSON Summary..."
jq -n \
  --argjson total_queries "$total_queries" \
  --argjson total_success "$total_success" \
  --argjson total_failed "$total_failed" \
  --argjson error_percent "$error_percent" \
  --argjson min_time "$min_time" \
  --argjson max_time "$max_time" \
  --argjson avg_time "$avg_time" \
  '{
    "total_queries": $total_queries,
    "total_success": $total_success,
    "total_failed": $total_failed,
    "error_percent": $error_percent,
    "min_time": $min_time,
    "max_time": $max_time,
    "avg_time": $avg_time
  }' >> "$CONFIG_FILE"


# Extract statistics from Aggregate Report for test_results file

# Ensure variables are safe for JSON generation
total_queries=${total_queries:-0}
total_success=${total_success:-0}
total_failed=${total_failed:-0}
total_time_taken=${total_time_taken:-0}
error_percent=${error_percent:-"0.00"}
min_time=${min_time:-"0"}
max_time=${max_time:-"0"}
avg_time=${avg_time:-"0"}
median_time=${median_time:-"0"}
throughput=${throughput:-"0"}
unique_queries=${unique_queries:-"0"}
p50_latency=${p50_latency:-"0"}
p90_latency=${p90_latency:-"0"}
p95_latency=${p95_latency:-"0"}
p99_latency=${p99_latency:-"0"}
query_timings=${query_timings:-"0"}
top_10_json=${top_10_json:-"0"}
all_queries_json=${all_queries_json:-"0"}
bootstrap_query_count=${bootstrap_query_count:-"0"}
jsr_sampler_count=${jsr_sampler_count:-"0"}
jdbc_sampler_count=${jsr_sampler_count:-"0"}
actual_considered_queries=${actual_considered_queries:-null}

# Set default values for variables (ensure they are valid JSON)
#jmeter_summary=${jmeter_summary:-'{}'}

bootstrap_query_count=${bootstrap_query_count:-"0"}
jsr_sampler_count=${jsr_sampler_count:-0}
jdbc_sampler_count=${jdbc_sampler_count:-0}

total_queries=${total_queries:-0}
total_success=${total_success:-0}
total_failed=${total_failed:-0}
error_percent=${error_percent:-0}
throughput=${throughput:-0}

total_time_taken=${total_time_taken:-0}
total_time_taken_sec=${total_time_taken_sec:-0}
min_time=${min_time:-0}
max_time=${max_time:-0}
avg_time=${avg_time:-0}
median_time=${median_time:-0}

p50_latency=${p50_latency:-0}
p90_latency=${p90_latency:-0}
p95_latency=${p95_latency:-0}
p99_latency=${p99_latency:-0}


all_queries_json=${all_queries_json:-'[]'}
unique_queries=${unique_queries:-'[]'}
bootstrap_queries=${bootstrap_queries:-'[]'}
actual_considered_queries=${actual_considered_queries:-'[]'}
top_10_json=${top_10_json:-'[]'}


if [[ -f "$AGGREGATE_REPORT" ]]; then
HEADERS=$(head -1 "$AGGREGATE_REPORT" | awk -F',' '{for(i=1;i<=NF;i++) gsub(/"/,"",$i); print tolower($0)}')


# Calculate query type counts
total_query_count=$(awk -F',' 'NR>1 {count++} END {print count}' "$AGGREGATE_REPORT")
bootstrap_query_count=$(awk -F',' 'NR>1 && $3 ~ /BOOTSTRAP/ {count++} END {print count}' "$AGGREGATE_REPORT")
jsr_sampler_count=$(awk -F',' 'NR>1 && $3 ~ /JSR/ {count++} END {print count}' "$AGGREGATE_REPORT")
jdbc_sampler_count=$(awk -F',' 'NR>1 && $3 !~ /BOOTSTRAP/ && $3 !~ /JSR/ {count++} END {print count}' "$AGGREGATE_REPORT")
actual_considered_queries=$jdbc_sampler_count

# Extract relevant stats
total_queries=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ {count++} END {print count}' "$AGGREGATE_REPORT")
total_success=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ && $4==200 {count++} END {print count}' "$AGGREGATE_REPORT")
total_failed=$((total_queries - total_success))
total_time_taken=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ {sum+=$2/1000} END {print sum}' "$AGGREGATE_REPORT")
min_time=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ && $4==200 {print $2}' "$AGGREGATE_REPORT" | sort -n | head -1 | awk '{printf "%.2f", $1/1000}')
max_time=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ && $4==200 {print $2}' "$AGGREGATE_REPORT" | sort -n | tail -1 | awk '{printf "%.2f", $1/1000}')
avg_time=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ && $4==200 {count++; sum+=$2} END {if (count>0) printf "%.2f", (sum/count)/1000}' "$AGGREGATE_REPORT")
median_time=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ && $4==200 {print $2}' "$AGGREGATE_REPORT" | sort -n | awk 'NF{a[i++]=$1} END{printf "%.2f", (i%2==1?a[int(i/2)]:(a[i/2-1]+a[i/2])/2)/1000}')
unique_queries=$(awk -F',' 'NR>1 {gsub(/^"|"$/, "", $3); if ($3 !~ /(BOOTSTRAP|JSR)/) seen[$3]++} END {print length(seen)}' "$AGGREGATE_REPORT")
error_percent=$(awk "BEGIN {printf \"%.2f\", ($total_failed/$total_queries) * 100}")
throughput=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ && $4==200 {count++; sum+=$2} END {if (sum>0) printf "%.2f", (count/(sum/1000))}' "$AGGREGATE_REPORT")
p50_latency=$median_time

# Calculate percentiles (p90, p95, p99)
sorted_values=$(awk -F',' 'NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ {print $2}' "$AGGREGATE_REPORT" | sort -n)
tpcds_count=$(echo "$sorted_values" | wc -l)

p90_index=$(echo "($tpcds_count * 90 / 100) + 1" | bc)
p95_index=$(echo "($tpcds_count * 95 / 100) + 1" | bc)
p99_index=$(echo "($tpcds_count * 99 / 100) + 1" | bc)

[[ $p90_index -gt $tpcds_count ]] && p90_index=$tpcds_count
[[ $p95_index -gt $tpcds_count ]] && p95_index=$tpcds_count
[[ $p99_index -gt $tpcds_count ]] && p99_index=$tpcds_count

p90_latency=$(echo "$sorted_values" | sed -n "${p90_index}p" | awk '{printf "%.2f", $1/1000}')
p95_latency=$(echo "$sorted_values" | sed -n "${p95_index}p" | awk '{printf "%.2f", $1/1000}')
p99_latency=$(echo "$sorted_values" | sed -n "${p99_index}p" | awk '{printf "%.2f", $1/1000}')



    # Calculate query timings
    query_timings=$(awk -F',' '
    BEGIN {
        printf "["
        first = 1
    }
    NR>1 && $3 !~ /(BOOTSTRAP|JSR)/ {
        label=$3
        gsub(/^"|"$/, "", label)  # Remove quotes
        time=$2
        count[label]++
        sum[label]+=time
    }
    END {
        for (label in sum) {
            avg=sum[label]/count[label]/1000
            if (!first) printf ","
            printf "{\"query\":\"%s\",\"avg_time_sec\":%.2f}", label, avg
            first=0
        }
        printf "]"
    }' "$AGGREGATE_REPORT" | sort -t: -k4,4nr)

    # Set both arrays to the same value for now
    top_10_json="$query_timings"
    all_queries_json="$query_timings"

# Create JSON summary
# Ensure jmeter_summary is a valid JSON object (default to empty object if empty)
#jmeter_summary=${jmeter_summary:-"{}"}

JSON_SUMMARY=$(jq -n \
    --arg run_id "$RUN_ID" \
    --arg run_date "$RUN_DATE" \
    --arg start_time "$START_TIME" \
    --arg end_time "$END_TIME" \
    --arg alias "$ALIAS" \
    --arg engine "$ENGINE" \
    --arg jmeter_hostname "$JMETER_HOSTNAME" \
    --arg cluster_hostname "$CLUSTER_HOSTNAME" \
    --arg cloud "$CLOUD" \
    --arg mode "$MODE" \
    --arg tags "$TAGS" \
    --arg comments "$COMMENTS" \
    --argjson cluster_config "$CLUSTER_CONFIG" \
    --arg autoscale "$AUTOSCALE" \
    --arg data_type "$DATA_TYPE" \
    --arg additional_info "$ADDITIONAL_INFO" \
    --arg jmeter_run_summary "$JMETER_RUN_SUMMARY" \
    --argjson top_10_json "$top_10_json" \
    --argjson all_queries_json "$all_queries_json" \
    --argjson total_query_count "${total_query_count:-0}" \
    --argjson bootstrap_query_count "${bootstrap_query_count:-0}" \
    --argjson jsr_sampler_count "${jsr_sampler_count:-0}" \
    --argjson jdbc_sampler_count "${jdbc_sampler_count:-0}" \
    --argjson actual_considered_queries "$actual_considered_queries" \
    --argjson total_queries "${total_queries:-0}" \
    --argjson total_success "${total_success:-0}" \
    --argjson total_failed "${total_failed:-0}" \
    --argjson total_time_taken "${total_time_taken:-0}" \
    --argjson min_time "${min_time:-0}" \
    --argjson max_time "${max_time:-0}" \
    --argjson avg_time "${avg_time:-0}" \
    --argjson median_time "${median_time:-0}" \
    --argjson p50_latency "${p50_latency:-0}" \
    --argjson p90_latency "${p90_latency:-0}" \
    --argjson p95_latency "${p95_latency:-0}" \
    --argjson p99_latency "${p99_latency:-0}" \
    --argjson unique_queries "$unique_queries" \
    --argjson error_percent "$error_percent" \
    --argjson throughput "$throughput" \
    --arg report_path "$REPORT_PATH" \
    --arg aggregate_report "$AGGREGATE_REPORT" \
    '{
        run_id: $run_id,
    	run_date:$run_date,
    	start_time:$start_time,
    	end_time:$end_time,
    	alias:$alias,
    	engine:$engine,
	jmeter_hostname:$jmeter_hostname,
	cluster_hostname:$cluster_hostname,
	cloud:$cloud,
	mode:$mode,
	tags:$tags,
	comments:$comments,
	autoscale:$autoscale,
	data_type:$data_type,
	additional_info:$additional_info,
	jmeter_run_summary: $jmeter_run_summary,
        total_query_count: $total_query_count,
        bootstrap_query_count: $bootstrap_query_count,
        jsr_sampler_count: $jsr_sampler_count,
        jdbc_sampler_count: $jdbc_sampler_count,
        actual_considered_queries: $actual_considered_queries,
        total_queries: $total_queries,
        total_success: $total_success,
        total_failed: $total_failed,
        total_time_taken_sec: $total_time_taken,
        min_time_sec: $min_time,
        max_time_sec: $max_time,
        avg_time_sec: $avg_time,
        median_time_sec: $median_time,
        p50_latency_sec: $p50_latency,
        p90_latency_sec: $p90_latency,
        p95_latency_sec: $p95_latency,
        p99_latency_sec: $p99_latency,
        unique_queries: $unique_queries,
        error_percent: $error_percent,
        throughput: $throughput,
        report_path: $report_path,
        aggregate_report: $aggregate_report,
	      cluster_config:$cluster_config,
        top_10_time_consuming_queries: $top_10_json,
        all_queries_avg_time: $all_queries_json
    }')
fi

# Ensure JSON generation succeeded before proceeding
if [[ $? -ne 0 || -z "$JSON_SUMMARY" ]]; then
    echo "Failed to generate JSON summary. Check jq syntax or input values."
    exit 1
fi

# Write the json summary to the TEST_RESULT_FILE...
echo "$JSON_SUMMARY" > "$TEST_RESULT_FILE"


# Define S3 path with run_date and run_id as partitions
S3_PATH_WITH_PARTITIONS="s3://e6-jmeter/jmeter-results/run_date=$RUN_DATE/run_id=$RUN_ID"

#Rename the statistics.json file with the run_ID
mv ${STATISTICS_FILE} ${STATISTICS_FILE}_${RUN_ID}
STATISTICS_FILE="${STATISTICS_FILE}_${RUN_ID}"



# Copy results to S3 (if COPY_TO_S3 is true)
if [[ "$COPY_TO_S3" == "true" ]]; then
    echo "Copying results to S3 with partitions..."
    FILES_TO_COPY=("$JMETER_RESULT_FILE" "$AGGREGATE_REPORT" "$SUMMARY_REPORT" "$CONFIG_FILE" "$TEST_RESULT_FILE" "$STATISTICS_FILE")
    S3_ERROR=0

    for file in "${FILES_TO_COPY[@]}"; do
        if [[ -f "$file" ]]; then
            if aws s3 cp "$file" "$S3_PATH_WITH_PARTITIONS/"; then
                echo "✅ Successfully uploaded: $file"
            else
                echo "❌ Failed to upload: $file"
                S3_ERROR=1
            fi
        else
            echo "⚠️ File not found, skipping: $file"
        fi
    done

    if [[ $S3_ERROR -eq 0 ]]; then
        echo "✅ All files copied to S3 successfully!"
    else
        echo "❌ Some files failed to copy to S3. Please check logs."
    fi

# After S3 copy succeeds, add Athena partitions
if [[ $S3_ERROR -eq 0 ]]; then
    echo "Adding Athena partitions..."
    
    # Define all tables needing partitions
    declare -A TABLE_PATHS=(
        ["detailed_results"]="run_date=$RUN_DATE/run_id=$RUN_ID/JmeterResultFile_$RUN_ID.csv"
        ["aggregate_report"]="run_date=$RUN_DATE/run_id=$RUN_ID/AggregateReport_$RUN_ID.csv"
        ["run_metadata"]="run_date=$RUN_DATE/run_id=$RUN_ID/test_config_$RUN_ID.json"
        ["run_summary"]="run_date=$RUN_DATE/run_id=$RUN_ID/test_result_$RUN_ID.json"
        ["statistics"]="run_date=$RUN_DATE/run_id=$RUN_ID/statistics_$RUN_ID.json"
    )
    
    for table in "${!TABLE_PATHS[@]}"; do
        echo "  Adding partition for $table..."
        aws athena start-query-execution \
            --query-string "ALTER TABLE jmeter_performance_db.$table ADD PARTITION (run_date='$RUN_DATE', run_id='$RUN_ID') LOCATION 's3://e6-jmeter/jmeter-results/${TABLE_PATHS[$table]}'" \
            --query-execution-context Database=jmeter_performance_db \
            --result-configuration OutputLocation=s3://e6-jmeter/athena-query-results/ &
    done
    wait

echo "Test and Upload Process Complete! "
echo "Test Result folder :  $S3_PATH_WITH_PARTITIONS"
echo "Test Results : $TEST_RESULT_FILE"
fi

else
    echo "⏩ Skipping S3 copy (COPY_TO_S3 is not true)."
fi

echo "Test Results :"
cat $TEST_RESULT_FILE
exit 0

