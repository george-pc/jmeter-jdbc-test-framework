#!/bin/bash
# Run all e6data Medium (M) cluster concurrency tests sequentially
# Concurrency levels: 2, 4, 8, 12, 16

set -e

# Configuration
ENGINE="e6data"
CLUSTER_SIZE="M"
CONCURRENCY_LEVELS=(2 4 8 12 16)
S3_BASE_PATH="s3://e6-jmeter/jmeter-results"
BENCHMARK="tpcds_29_1tb"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Navigate to project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}=========================================="
echo "e6data Medium (M) Cluster - All Concurrency Tests"
echo -e "==========================================${NC}"
echo ""
echo "⚠️  IMPORTANT: Ensure e6data cluster is configured for MEDIUM (M) workload before running!"
echo ""
echo "Tests to run:"
for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
    echo "  - Concurrency: ${concurrency} threads"
done
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Create log directory
LOG_DIR="/tmp/jmeter_test_logs"
mkdir -p "$LOG_DIR"

# Run all concurrency tests
for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
    TEST_INPUT="test_inputs/${ENGINE}_${CLUSTER_SIZE,,}_tpcds29_concurrency_${concurrency}.txt"
    LOG_FILE="$LOG_DIR/${ENGINE}_${CLUSTER_SIZE,,}_concurrency${concurrency}_$(date +%Y%m%d_%H%M%S).log"

    echo ""
    echo -e "${BLUE}=========================================="
    echo "Running: e6data ${CLUSTER_SIZE} - Concurrency ${concurrency}"
    echo -e "==========================================${NC}"
    echo "Test input: $TEST_INPUT"
    echo "Log file: $LOG_FILE"
    echo ""

    # Run test
    if ./run_jmeter_tests_interactive.sh < "$TEST_INPUT" 2>&1 | tee "$LOG_FILE"; then
        echo -e "${GREEN}✓ Test completed: Concurrency ${concurrency}${NC}"
    else
        echo -e "${YELLOW}⚠ Test failed or interrupted: Concurrency ${concurrency}${NC}"
        echo "Check log: $LOG_FILE"
        read -p "Continue with next test? (y/n): " continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            echo "Exiting..."
            exit 1
        fi
    fi

    # Wait between tests
    if [[ "$concurrency" != "${CONCURRENCY_LEVELS[-1]}" ]]; then
        echo ""
        echo "Waiting 30 seconds before next test..."
        sleep 30
    fi
done

echo ""
echo -e "${GREEN}=========================================="
echo "✓ All e6data ${CLUSTER_SIZE} concurrency tests completed!"
echo -e "==========================================${NC}"
echo ""
echo "Logs saved in: $LOG_DIR"
echo ""
echo "Next steps:"
echo "  1. Check S3 for uploaded results:"
echo "     ${S3_BASE_PATH}/engine=${ENGINE}/cluster_size=${CLUSTER_SIZE}/benchmark=${BENCHMARK}/run_type=concurrency_X/run_id=YYYYMMDD-HHMMSS/"
echo "  2. Compare results using utilities/compare_s3_runs.sh"
echo ""
