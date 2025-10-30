#!/bin/bash
# Run all Databricks Small S-4x4 cluster (120 cores) concurrency tests sequentially
# Concurrency levels: 2, 4, 8, 12, 16
# This configuration matches e6data M-4x4 (120 cores) for fair comparison

set -e

# Configuration
ENGINE="databricks"
CLUSTER_SIZE="S-4x4"
CONCURRENCY_LEVELS=(2 4 8 12 16)

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Navigate to project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo -e "${BLUE}=========================================="
echo "Databricks S-4x4 Cluster (~120 cores) - All Concurrency Tests"
echo -e "==========================================${NC}"
echo ""
echo "⚠️  IMPORTANT: Configure Databricks warehouse BEFORE running:"
echo "   - Warehouse Size: Small"
echo "   - Min Clusters: 4"
echo "   - Max Clusters: 4"
echo "   - This provides ~120 cores, equivalent to e6data M-4x4"
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
    TEST_INPUT="test_inputs/databricks_s-4x4_tpcds29_concurrency_${concurrency}.txt"
    LOG_FILE="$LOG_DIR/${ENGINE}_s-4x4_concurrency${concurrency}_$(date +%Y%m%d_%H%M%S).log"

    echo ""
    echo -e "${BLUE}=========================================="
    echo "Running: Databricks ${CLUSTER_SIZE} - Concurrency ${concurrency}"
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
echo "✓ All Databricks ${CLUSTER_SIZE} concurrency tests completed!"
echo -e "==========================================${NC}"
echo ""
echo "Logs saved in: $LOG_DIR"
echo ""
echo "Next steps:"
echo "  1. Check S3 for uploaded results:"
echo "     s3://e6-jmeter/jmeter-results/engine=databricks/cluster_size=S-4x4/benchmark=tpcds_29_1tb/"
echo "  2. Compare with e6data M-4x4 results:"
echo "     s3://e6-jmeter/jmeter-results/engine=e6data/cluster_size=M-4x4/benchmark=tpcds_29_1tb/"
echo ""
