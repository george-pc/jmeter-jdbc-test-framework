#!/usr/bin/env python3
"""
JMeter Test Run Comparison Tool

Compares two JMeter test runs using their test_result.json files.
Provides detailed analysis of performance differences, configuration changes,
and query-level comparisons.

Usage:
    python compare_jmeter_runs.py <run1_result.json> <run2_result.json> [--format {text|json|markdown}]

Examples:
    # Compare two local files
    python compare_jmeter_runs.py reports/test_result_20251029-083259.json reports/test_result_20251029-084324.json

    # Compare from S3
    python compare_jmeter_runs.py s3://bucket/run1/test_result.json s3://bucket/run2/test_result.json

    # Output as markdown
    python compare_jmeter_runs.py run1.json run2.json --format markdown > comparison.md
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Any
import subprocess


def load_json_file(file_path: str) -> Dict:
    """Load JSON from local file or S3."""
    if file_path.startswith('s3://'):
        # Download from S3 using AWS CLI
        try:
            result = subprocess.run(
                ['aws', 's3', 'cp', file_path, '-'],
                capture_output=True,
                text=True,
                check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error downloading from S3: {e}", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON from S3: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Load from local file
        try:
            with open(file_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"Error: File not found: {file_path}", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"Error parsing JSON: {e}", file=sys.stderr)
            sys.exit(1)


def calculate_percentage_change(old_value: float, new_value: float) -> float:
    """Calculate percentage change between two values."""
    if old_value == 0:
        return 0 if new_value == 0 else 100
    return ((new_value - old_value) / old_value) * 100


def format_percentage(value: float, inverse: bool = False) -> str:
    """Format percentage with color indicators.

    Args:
        value: Percentage change
        inverse: If True, negative is good (like for latency reduction)
    """
    if value == 0:
        return "  0.00% (no change)"

    symbol = "↓" if value < 0 else "↑"
    color_indicator = ""

    if inverse:
        # For metrics where lower is better (latency, errors)
        if value < 0:
            color_indicator = "✅"  # Improvement
        elif value > 0:
            color_indicator = "⚠️"   # Degradation
    else:
        # For metrics where higher is better (throughput)
        if value > 0:
            color_indicator = "✅"  # Improvement
        elif value < 0:
            color_indicator = "⚠️"   # Degradation

    return f"{symbol} {abs(value):6.2f}% {color_indicator}"


def compare_configurations(run1: Dict, run2: Dict) -> List[str]:
    """Compare test execution configurations."""
    differences = []

    # Compare test execution config
    config1 = run1.get('test_execution_config', {})
    config2 = run2.get('test_execution_config', {})

    config_fields = [
        ('test_plan_file', 'Test Plan'),
        ('concurrent_threads', 'Concurrent Threads'),
        ('ramp_up_time_min', 'Ramp Up Time (min)'),
        ('hold_period_min', 'Hold Period (min)'),
        ('recycle_on_eof', 'Recycle on EOF'),
        ('random_order', 'Random Order'),
        ('query_timeout_sec', 'Query Timeout (sec)'),
        ('qpm', 'QPM'),
        ('qps', 'QPS'),
    ]

    for field, label in config_fields:
        val1 = config1.get(field, 'N/A')
        val2 = config2.get(field, 'N/A')
        if val1 != val2:
            differences.append(f"  {label}: {val1} → {val2}")

    # Compare cluster config
    cluster1 = run1.get('cluster_config', {})
    cluster2 = run2.get('cluster_config', {})

    if cluster1 != cluster2:
        differences.append(f"  Cluster Config: Different")

    return differences


def compare_query_performance(run1: Dict, run2: Dict) -> Tuple[List[Dict], List[Dict], List[str]]:
    """Compare individual query performance.

    Returns:
        (improved_queries, degraded_queries, missing_queries)
    """
    queries1 = {q['query']: q['avg_time_sec'] for q in run1.get('all_queries_avg_time', [])}
    queries2 = {q['query']: q['avg_time_sec'] for q in run2.get('all_queries_avg_time', [])}

    improved = []
    degraded = []
    missing = []

    for query_name, time1 in queries1.items():
        if query_name not in queries2:
            missing.append(f"  {query_name}: Only in Run 1")
            continue

        time2 = queries2[query_name]
        change = calculate_percentage_change(time1, time2)

        query_comparison = {
            'query': query_name,
            'run1_time': time1,
            'run2_time': time2,
            'change_pct': change,
            'change_sec': time2 - time1
        }

        if change < -5:  # Improved by more than 5%
            improved.append(query_comparison)
        elif change > 5:  # Degraded by more than 5%
            degraded.append(query_comparison)

    # Check for queries only in run2
    for query_name in queries2:
        if query_name not in queries1:
            missing.append(f"  {query_name}: Only in Run 2")

    # Sort by absolute change
    improved.sort(key=lambda x: x['change_pct'])
    degraded.sort(key=lambda x: x['change_pct'], reverse=True)

    return improved, degraded, missing


def generate_text_comparison(run1: Dict, run2: Dict) -> str:
    """Generate text format comparison report."""
    output = []

    output.append("=" * 100)
    output.append("JMETER TEST RUN COMPARISON")
    output.append("=" * 100)
    output.append("")

    # Run identification
    output.append("RUN IDENTIFICATION")
    output.append("-" * 100)
    output.append(f"Run 1: {run1.get('run_id', 'unknown')} ({run1.get('engine', 'unknown')} on {run1.get('cloud', 'unknown')})")
    output.append(f"       Cluster: {run1.get('cluster_hostname', 'unknown')}")
    output.append(f"       Started: {run1.get('start_time', 'unknown')}")
    output.append("")
    output.append(f"Run 2: {run2.get('run_id', 'unknown')} ({run2.get('engine', 'unknown')} on {run2.get('cloud', 'unknown')})")
    output.append(f"       Cluster: {run2.get('cluster_hostname', 'unknown')}")
    output.append(f"       Started: {run2.get('start_time', 'unknown')}")
    output.append("")

    # Configuration differences
    config_diffs = compare_configurations(run1, run2)
    output.append("CONFIGURATION DIFFERENCES")
    output.append("-" * 100)
    if config_diffs:
        output.extend(config_diffs)
    else:
        output.append("  No configuration differences detected")
    output.append("")

    # Performance summary comparison
    output.append("PERFORMANCE SUMMARY")
    output.append("-" * 100)
    output.append(f"{'Metric':<30} {'Run 1':>15} {'Run 2':>15} {'Change':>20}")
    output.append("-" * 100)

    metrics = [
        ('Total Queries', 'total_queries', False),
        ('Successful', 'total_success', False),
        ('Failed', 'total_failed', True),
        ('Error Rate %', 'error_percent', True),
        ('Total Duration (sec)', 'total_time_taken_sec', True),
        ('Avg Response (sec)', 'avg_time_sec', True),
        ('Median (p50) (sec)', 'p50_latency_sec', True),
        ('p90 Latency (sec)', 'p90_latency_sec', True),
        ('p95 Latency (sec)', 'p95_latency_sec', True),
        ('p99 Latency (sec)', 'p99_latency_sec', True),
        ('Min Response (sec)', 'min_time_sec', True),
        ('Max Response (sec)', 'max_time_sec', True),
        ('Throughput (q/s)', 'throughput', False),
    ]

    for label, key, inverse in metrics:
        val1 = run1.get(key, 0)
        val2 = run2.get(key, 0)

        if isinstance(val1, (int, float)) and isinstance(val2, (int, float)):
            change_pct = calculate_percentage_change(val1, val2)
            change_str = format_percentage(change_pct, inverse)
            output.append(f"{label:<30} {val1:>15.2f} {val2:>15.2f} {change_str:>20}")
        else:
            output.append(f"{label:<30} {str(val1):>15} {str(val2):>15} {'N/A':>20}")

    output.append("")

    # Query-level comparison
    improved, degraded, missing = compare_query_performance(run1, run2)

    output.append("TOP 10 IMPROVED QUERIES")
    output.append("-" * 100)
    if improved:
        output.append(f"{'Query':<50} {'Run 1 (s)':>12} {'Run 2 (s)':>12} {'Change':>20}")
        output.append("-" * 100)
        for q in improved[:10]:
            change_str = format_percentage(q['change_pct'], inverse=True)
            output.append(f"{q['query']:<50} {q['run1_time']:>12.2f} {q['run2_time']:>12.2f} {change_str:>20}")
    else:
        output.append("  No significantly improved queries (threshold: 5% improvement)")
    output.append("")

    output.append("TOP 10 DEGRADED QUERIES")
    output.append("-" * 100)
    if degraded:
        output.append(f"{'Query':<50} {'Run 1 (s)':>12} {'Run 2 (s)':>12} {'Change':>20}")
        output.append("-" * 100)
        for q in degraded[:10]:
            change_str = format_percentage(q['change_pct'], inverse=True)
            output.append(f"{q['query']:<50} {q['run1_time']:>12.2f} {q['run2_time']:>12.2f} {change_str:>20}")
    else:
        output.append("  No significantly degraded queries (threshold: 5% degradation)")
    output.append("")

    if missing:
        output.append("MISSING QUERIES")
        output.append("-" * 100)
        output.extend(missing)
        output.append("")

    # Summary verdict
    output.append("SUMMARY VERDICT")
    output.append("-" * 100)

    avg_change = calculate_percentage_change(
        run1.get('avg_time_sec', 0),
        run2.get('avg_time_sec', 0)
    )

    if avg_change < -10:
        verdict = "✅ SIGNIFICANT IMPROVEMENT"
        details = f"Run 2 is {abs(avg_change):.1f}% faster than Run 1"
    elif avg_change < -5:
        verdict = "✅ MODERATE IMPROVEMENT"
        details = f"Run 2 is {abs(avg_change):.1f}% faster than Run 1"
    elif avg_change > 10:
        verdict = "⚠️  SIGNIFICANT DEGRADATION"
        details = f"Run 2 is {avg_change:.1f}% slower than Run 1"
    elif avg_change > 5:
        verdict = "⚠️  MODERATE DEGRADATION"
        details = f"Run 2 is {avg_change:.1f}% slower than Run 1"
    else:
        verdict = "➖ SIMILAR PERFORMANCE"
        details = f"Performance difference is within 5% (actual: {avg_change:.1f}%)"

    output.append(f"  {verdict}")
    output.append(f"  {details}")
    output.append("")
    output.append(f"  Improved queries: {len(improved)}")
    output.append(f"  Degraded queries: {len(degraded)}")
    output.append(f"  Similar queries: {run1.get('total_queries', 0) - len(improved) - len(degraded)}")
    output.append("")

    output.append("=" * 100)

    return "\n".join(output)


def generate_json_comparison(run1: Dict, run2: Dict) -> str:
    """Generate JSON format comparison report."""
    improved, degraded, missing = compare_query_performance(run1, run2)

    comparison = {
        'run1': {
            'run_id': run1.get('run_id'),
            'engine': run1.get('engine'),
            'cloud': run1.get('cloud'),
            'cluster': run1.get('cluster_hostname'),
            'start_time': run1.get('start_time'),
        },
        'run2': {
            'run_id': run2.get('run_id'),
            'engine': run2.get('engine'),
            'cloud': run2.get('cloud'),
            'cluster': run2.get('cluster_hostname'),
            'start_time': run2.get('start_time'),
        },
        'config_differences': compare_configurations(run1, run2),
        'performance_comparison': {
            'total_queries': {
                'run1': run1.get('total_queries'),
                'run2': run2.get('total_queries'),
                'change_pct': calculate_percentage_change(run1.get('total_queries', 0), run2.get('total_queries', 0))
            },
            'avg_response_time_sec': {
                'run1': run1.get('avg_time_sec'),
                'run2': run2.get('avg_time_sec'),
                'change_pct': calculate_percentage_change(run1.get('avg_time_sec', 0), run2.get('avg_time_sec', 0))
            },
            'p50_latency_sec': {
                'run1': run1.get('p50_latency_sec'),
                'run2': run2.get('p50_latency_sec'),
                'change_pct': calculate_percentage_change(run1.get('p50_latency_sec', 0), run2.get('p50_latency_sec', 0))
            },
            'p95_latency_sec': {
                'run1': run1.get('p95_latency_sec'),
                'run2': run2.get('p95_latency_sec'),
                'change_pct': calculate_percentage_change(run1.get('p95_latency_sec', 0), run2.get('p95_latency_sec', 0))
            },
            'p99_latency_sec': {
                'run1': run1.get('p99_latency_sec'),
                'run2': run2.get('p99_latency_sec'),
                'change_pct': calculate_percentage_change(run1.get('p99_latency_sec', 0), run2.get('p99_latency_sec', 0))
            },
            'throughput': {
                'run1': run1.get('throughput'),
                'run2': run2.get('throughput'),
                'change_pct': calculate_percentage_change(run1.get('throughput', 0), run2.get('throughput', 0))
            },
            'error_percent': {
                'run1': run1.get('error_percent'),
                'run2': run2.get('error_percent'),
                'change_pct': calculate_percentage_change(run1.get('error_percent', 0), run2.get('error_percent', 0))
            }
        },
        'query_analysis': {
            'improved_queries': improved[:10],
            'degraded_queries': degraded[:10],
            'missing_queries': missing,
            'total_improved': len(improved),
            'total_degraded': len(degraded),
            'total_missing': len(missing)
        }
    }

    return json.dumps(comparison, indent=2)


def generate_markdown_comparison(run1: Dict, run2: Dict) -> str:
    """Generate Markdown format comparison report."""
    output = []

    output.append("# JMeter Test Run Comparison Report")
    output.append("")

    # Run identification
    output.append("## Run Identification")
    output.append("")
    output.append("| Aspect | Run 1 | Run 2 |")
    output.append("|--------|-------|-------|")
    output.append(f"| Run ID | {run1.get('run_id', 'unknown')} | {run2.get('run_id', 'unknown')} |")
    output.append(f"| Engine | {run1.get('engine', 'unknown')} | {run2.get('engine', 'unknown')} |")
    output.append(f"| Cloud | {run1.get('cloud', 'unknown')} | {run2.get('cloud', 'unknown')} |")
    output.append(f"| Cluster | {run1.get('cluster_hostname', 'unknown')} | {run2.get('cluster_hostname', 'unknown')} |")
    output.append(f"| Started | {run1.get('start_time', 'unknown')} | {run2.get('start_time', 'unknown')} |")
    output.append("")

    # Configuration differences
    config_diffs = compare_configurations(run1, run2)
    output.append("## Configuration Differences")
    output.append("")
    if config_diffs:
        for diff in config_diffs:
            output.append(f"- {diff.strip()}")
    else:
        output.append("*No configuration differences detected*")
    output.append("")

    # Performance comparison
    output.append("## Performance Summary")
    output.append("")
    output.append("| Metric | Run 1 | Run 2 | Change |")
    output.append("|--------|-------|-------|--------|")

    metrics = [
        ('Total Queries', 'total_queries', False),
        ('Error Rate %', 'error_percent', True),
        ('Avg Response (sec)', 'avg_time_sec', True),
        ('Median (p50) (sec)', 'p50_latency_sec', True),
        ('p95 Latency (sec)', 'p95_latency_sec', True),
        ('p99 Latency (sec)', 'p99_latency_sec', True),
        ('Throughput (q/s)', 'throughput', False),
    ]

    for label, key, inverse in metrics:
        val1 = run1.get(key, 0)
        val2 = run2.get(key, 0)
        change_pct = calculate_percentage_change(val1, val2)
        change_str = format_percentage(change_pct, inverse)
        output.append(f"| {label} | {val1:.2f} | {val2:.2f} | {change_str} |")

    output.append("")

    # Query comparisons
    improved, degraded, missing = compare_query_performance(run1, run2)

    output.append("## Top 10 Improved Queries")
    output.append("")
    if improved:
        output.append("| Query | Run 1 (s) | Run 2 (s) | Change |")
        output.append("|-------|-----------|-----------|--------|")
        for q in improved[:10]:
            change_str = format_percentage(q['change_pct'], inverse=True)
            output.append(f"| {q['query']} | {q['run1_time']:.2f} | {q['run2_time']:.2f} | {change_str} |")
    else:
        output.append("*No significantly improved queries*")
    output.append("")

    output.append("## Top 10 Degraded Queries")
    output.append("")
    if degraded:
        output.append("| Query | Run 1 (s) | Run 2 (s) | Change |")
        output.append("|-------|-----------|-----------|--------|")
        for q in degraded[:10]:
            change_str = format_percentage(q['change_pct'], inverse=True)
            output.append(f"| {q['query']} | {q['run1_time']:.2f} | {q['run2_time']:.2f} | {change_str} |")
    else:
        output.append("*No significantly degraded queries*")
    output.append("")

    # Summary verdict
    avg_change = calculate_percentage_change(
        run1.get('avg_time_sec', 0),
        run2.get('avg_time_sec', 0)
    )

    output.append("## Summary Verdict")
    output.append("")
    if avg_change < -10:
        output.append("✅ **SIGNIFICANT IMPROVEMENT**")
    elif avg_change < -5:
        output.append("✅ **MODERATE IMPROVEMENT**")
    elif avg_change > 10:
        output.append("⚠️ **SIGNIFICANT DEGRADATION**")
    elif avg_change > 5:
        output.append("⚠️ **MODERATE DEGRADATION**")
    else:
        output.append("➖ **SIMILAR PERFORMANCE**")

    output.append("")
    output.append(f"- Performance change: {avg_change:+.1f}%")
    output.append(f"- Improved queries: {len(improved)}")
    output.append(f"- Degraded queries: {len(degraded)}")
    output.append(f"- Similar queries: {run1.get('total_queries', 0) - len(improved) - len(degraded)}")
    output.append("")

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(
        description='Compare two JMeter test runs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('run1', help='Path to first test_result.json (local or s3://)')
    parser.add_argument('run2', help='Path to second test_result.json (local or s3://)')
    parser.add_argument(
        '--format',
        choices=['text', 'json', 'markdown'],
        default='text',
        help='Output format (default: text)'
    )

    args = parser.parse_args()

    # Load both runs
    print(f"Loading Run 1: {args.run1}", file=sys.stderr)
    run1 = load_json_file(args.run1)

    print(f"Loading Run 2: {args.run2}", file=sys.stderr)
    run2 = load_json_file(args.run2)

    print(f"Generating comparison...", file=sys.stderr)

    # Generate comparison in requested format
    if args.format == 'json':
        output = generate_json_comparison(run1, run2)
    elif args.format == 'markdown':
        output = generate_markdown_comparison(run1, run2)
    else:  # text
        output = generate_text_comparison(run1, run2)

    print(output)


if __name__ == '__main__':
    main()
