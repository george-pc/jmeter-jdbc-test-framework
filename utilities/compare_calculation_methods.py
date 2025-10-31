#!/usr/bin/env python3
"""
Compare manual CSV calculations vs JMeter statistics.json calculations.
"""

import json
import csv
from pathlib import Path

# Sample comparison for C=2
def main():
    # Load my manual CSV
    manual_data = {}
    csv_file = Path('reports/JPMC_Query_Latency_Comparison_AllConcurrencies.csv')

    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            query = row['Query']
            if query and not query.startswith('SUMMARY') and not query.startswith('Average'):
                manual_data[query] = {
                    'c2_avg': float(row['E6Data_C2_Avg(s)']) if row['E6Data_C2_Avg(s)'] else None,
                    'c2_median': float(row['E6Data_C2_Median(s)']) if row['E6Data_C2_Median(s)'] else None,
                    'c2_p90': float(row['E6Data_C2_p90(s)']) if row['E6Data_C2_p90(s)'] else None,
                    'c2_p95': float(row['E6Data_C2_p95(s)']) if row['E6Data_C2_p95(s)'] else None,
                    'c2_p99': float(row['E6Data_C2_p99(s)']) if row['E6Data_C2_p99(s)'] else None,
                }

    # Load JMeter statistics.json
    jmeter_data = {}
    stats_file = Path('/tmp/jpmc_stats_comparison/e6data_M_C2_statistics.json')

    with open(stats_file, 'r') as f:
        stats = json.load(f)

    # Map query names
    query_mapping = {
        'query-13-TPCDS-13-optimised': 'TPCDS-13',
        'query-14-TPCDS-14-optimised': 'TPCDS-14',
        'query-15-TPCDS-15': 'TPCDS-15',
        'query-18-TPCDS-18-optimised': 'TPCDS-18',
        'query-2-TPCDS-2': 'TPCDS-2',
        'query-22-TPCDS-22': 'TPCDS-22',
        'query-27-TPCDS-27-optimised': 'TPCDS-27',
        'query-28-TPCDS-28-optimised': 'TPCDS-28',
        'query-30-TPCDS-30': 'TPCDS-30',
        'query-35-TPCDS-35-optimised': 'TPCDS-35',
        'query-4-TPCDS-4-optimised': 'TPCDS-4',
        'query-41-TPCDS-41-optimised': 'TPCDS-41',
        'query-44-TPCDS-44-optimised': 'TPCDS-44',
        'query-50-TPCDS-50-optimised': 'TPCDS-50',
        'query-52-TPCDS-52-optimised': 'TPCDS-52',
        'query-54-TPCDS-54-optimised': 'TPCDS-54',
        'query-57-TPCDS-57-optimised': 'TPCDS-57',
        'query-58-TPCDS-58-optimised': 'TPCDS-58',
        'query-63-TPCDS-63': 'TPCDS-63',
        'query-65-TPCDS-65-optimised': 'TPCDS-65',
        'query-66-TPCDS-66': 'TPCDS-66',
        'query-69-TPCDS-69-optimised': 'TPCDS-69',
        'query-7-TPCDS-7-optimised': 'TPCDS-7',
        'query-75-TPCDS-75': 'TPCDS-75',
        'query-80-TPCDS-80': 'TPCDS-80',
        'query-82-TPCDS-82-optimised': 'TPCDS-82',
        'query-88-TPCDS-88-optimised': 'TPCDS-88',
        'query-9-TPCDS-9': 'TPCDS-9',
        'query-98-TPCDS-98-optimised': 'TPCDS-98',
    }

    for jmeter_name, common_name in query_mapping.items():
        if jmeter_name in stats and jmeter_name != 'Total':
            metrics = stats[jmeter_name]
            jmeter_data[common_name] = {
                'avg': metrics['meanResTime'] / 1000.0,
                'median': metrics['medianResTime'] / 1000.0,
                'p90': metrics['pct1ResTime'] / 1000.0,
                'p95': metrics['pct2ResTime'] / 1000.0,
                'p99': metrics['pct3ResTime'] / 1000.0,
            }

    # Compare
    print("=" * 120)
    print("COMPARISON: Manual CSV Calculation vs JMeter statistics.json")
    print("=" * 120)
    print(f"{'Query':<15} {'Metric':<10} {'Manual':<12} {'JMeter':<12} {'Diff (ms)':<12} {'Diff %':<10}")
    print("=" * 120)

    total_diffs = []

    for query in sorted(manual_data.keys()):
        if query in jmeter_data and manual_data[query]['c2_avg'] is not None:
            for metric in ['avg', 'median', 'p90', 'p95', 'p99']:
                manual_key = f'c2_{metric}'
                manual_val = manual_data[query][manual_key]
                jmeter_val = jmeter_data[query][metric]

                if manual_val is not None and jmeter_val is not None:
                    diff_ms = (manual_val - jmeter_val) * 1000
                    diff_pct = ((manual_val - jmeter_val) / jmeter_val * 100) if jmeter_val > 0 else 0

                    total_diffs.append(abs(diff_ms))

                    print(f"{query:<15} {metric:<10} {manual_val:<12.3f} {jmeter_val:<12.3f} {diff_ms:<12.1f} {diff_pct:<10.2f}%")

    print("=" * 120)
    print(f"\nTotal queries compared: {len([q for q in manual_data if q in jmeter_data])}")
    print(f"Average absolute difference: {sum(total_diffs) / len(total_diffs):.2f} ms")
    print(f"Max absolute difference: {max(total_diffs):.2f} ms")
    print(f"Min absolute difference: {min(total_diffs):.2f} ms")

    # Check for exact matches
    exact_matches = sum(1 for d in total_diffs if d < 1.0)
    print(f"Exact matches (< 1ms diff): {exact_matches} out of {len(total_diffs)} ({exact_matches/len(total_diffs)*100:.1f}%)")

if __name__ == '__main__':
    main()
