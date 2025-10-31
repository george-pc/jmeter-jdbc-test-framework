#!/usr/bin/env python3
"""
Analyze JPMC aggregate reports and create comprehensive comparison CSV.

Parses raw JMeter result CSVs and calculates query-level statistics.
"""

import csv
import sys
from pathlib import Path
from collections import defaultdict
import statistics

# Query name mapping: E6Data -> Databricks
QUERY_MAPPING = {
    'query-2-TPCDS-2': 'TPCDS-2',
    'query-4-TPCDS-4-optimised': 'TPCDS-4',
    'query-7-TPCDS-7-optimised': 'TPCDS-7',
    'query-9-TPCDS-9': 'TPCDS-9',
    'query-13-TPCDS-13-optimised': 'TPCDS-13',
    'query-14-TPCDS-14-optimised': 'TPCDS-14',
    'query-15-TPCDS-15': 'TPCDS-15',
    'query-18-TPCDS-18-optimised': 'TPCDS-18',
    'query-22-TPCDS-22': 'TPCDS-22',
    'query-27-TPCDS-27-optimised': 'TPCDS-27',
    'query-28-TPCDS-28-optimised': 'TPCDS-28',
    'query-30-TPCDS-30': 'TPCDS-30',
    'query-35-TPCDS-35-optimised': 'TPCDS-35',
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
    'query-75-TPCDS-75': 'TPCDS-75',
    'query-80-TPCDS-80': 'TPCDS-80',
    'query-82-TPCDS-82-optimised': 'TPCDS-82',
    'query-88-TPCDS-88-optimised': 'TPCDS-88',
    'query-98-TPCDS-98-optimised': 'TPCDS-98',
}


def parse_jmeter_csv(filepath):
    """Parse JMeter result CSV and extract query latencies."""
    query_latencies = defaultdict(list)

    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            label = row['label']

            # Skip bootstrap queries
            if 'BOOTSTRAP' in label.upper():
                continue

            # Get elapsed time in seconds
            elapsed_ms = int(row['elapsed'])
            elapsed_sec = elapsed_ms / 1000.0

            query_latencies[label].append(elapsed_sec)

    return query_latencies


def calculate_statistics(values):
    """Calculate summary statistics for a list of values."""
    if not values:
        return {
            'avg': 0.0,
            'median': 0.0,
            'p90': 0.0,
            'p95': 0.0,
            'p99': 0.0,
            'min': 0.0,
            'max': 0.0,
        }

    sorted_values = sorted(values)
    n = len(sorted_values)

    return {
        'avg': statistics.mean(values),
        'median': statistics.median(values),
        'p90': sorted_values[int(n * 0.90)] if n > 1 else sorted_values[0],
        'p95': sorted_values[int(n * 0.95)] if n > 1 else sorted_values[0],
        'p99': sorted_values[int(n * 0.99)] if n > 1 else sorted_values[0],
        'min': min(values),
        'max': max(values),
    }


def normalize_query_name(name, engine):
    """Normalize query name to common format."""
    # For E6Data, map to DBR format
    if engine == 'e6data':
        # Try exact match first
        if name in QUERY_MAPPING:
            return QUERY_MAPPING[name]
        # Try without query- prefix
        for e6_name, dbr_name in QUERY_MAPPING.items():
            if name in e6_name or e6_name in name:
                return dbr_name

    return name


def main():
    reports_dir = Path('reports/JPMC-Jmeter-Aggregate-Reports')

    if not reports_dir.exists():
        print(f"Error: {reports_dir} does not exist", file=sys.stderr)
        sys.exit(1)

    # Parse all files
    data = {}  # engine -> concurrency -> query -> stats

    for csv_file in reports_dir.glob('*.csv'):
        filename = csv_file.name

        # Parse filename: e6-M-Con-2-AggregateReport_*.csv or DBR-S-2x2-Con-2-AggregateReport_*.csv
        if filename.startswith('e6'):
            engine = 'e6data'
            if 'e6-M' in filename or 'e6data-M' in filename:
                cluster = 'M'
            elif 'e6-S' in filename:
                cluster = 'S-2x2'
            else:
                cluster = 'M'
        elif filename.startswith('DBR'):
            engine = 'databricks'
            if 'S-2x2' in filename:
                cluster = 'S-2x2'
            elif 'S-4x4' in filename:
                cluster = 'S-4x4'
            else:
                cluster = 'S-2x2'
        else:
            continue

        # Extract concurrency
        if '-Con-' in filename:
            parts = filename.split('-Con-')
            conc_str = parts[1].split('-')[0]
            concurrency = int(conc_str)
        else:
            continue

        # Parse CSV
        print(f"Processing {filename}...", file=sys.stderr)
        query_latencies = parse_jmeter_csv(csv_file)

        # Calculate stats
        key = f"{engine}_{cluster}"
        if key not in data:
            data[key] = {}
        if concurrency not in data[key]:
            data[key][concurrency] = {}

        for query, latencies in query_latencies.items():
            normalized_query = normalize_query_name(query, engine)
            stats = calculate_statistics(latencies)
            data[key][concurrency][normalized_query] = stats

    # Generate comparison CSV
    output_file = 'reports/JPMC_Query_Latency_Comparison_AllConcurrencies.csv'

    # Get all unique queries
    all_queries = set()
    for engine_data in data.values():
        for conc_data in engine_data.values():
            all_queries.update(conc_data.keys())
    all_queries = sorted(all_queries)

    # Get all concurrency levels
    all_concurrencies = sorted(set(
        conc for engine_data in data.values() for conc in engine_data.keys()
    ))

    # Build CSV
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)

        # Header
        header = ['Query']
        for conc in all_concurrencies:
            header.extend([
                f'E6Data_C{conc}_Avg(s)',
                f'E6Data_C{conc}_Median(s)',
                f'E6Data_C{conc}_p90(s)',
                f'E6Data_C{conc}_p95(s)',
                f'E6Data_C{conc}_p99(s)',
                f'E6Data_C{conc}_Min(s)',
                f'E6Data_C{conc}_Max(s)',
                f'DBR_C{conc}_Avg(s)',
                f'DBR_C{conc}_Median(s)',
                f'DBR_C{conc}_p90(s)',
                f'DBR_C{conc}_p95(s)',
                f'DBR_C{conc}_p99(s)',
                f'DBR_C{conc}_Min(s)',
                f'DBR_C{conc}_Max(s)',
                f'Diff_C{conc}_Avg(%)',
                f'Diff_C{conc}_Median(%)',
                f'Diff_C{conc}_p90(%)',
                f'Diff_C{conc}_p95(%)',
                f'Diff_C{conc}_p99(%)',
                f'Diff_C{conc}_Min(%)',
                f'Diff_C{conc}_Max(%)',
            ])
        writer.writerow(header)

        # Query data
        for query in all_queries:
            row = [query]

            for conc in all_concurrencies:
                # E6Data values
                e6_stats = None
                for key in data.keys():
                    if 'e6data' in key and conc in data[key] and query in data[key][conc]:
                        e6_stats = data[key][conc][query]
                        break

                # Databricks values
                dbr_stats = None
                for key in data.keys():
                    if 'databricks' in key and conc in data[key] and query in data[key][conc]:
                        dbr_stats = data[key][conc][query]
                        break

                # E6Data columns
                if e6_stats:
                    row.extend([
                        f"{e6_stats['avg']:.2f}",
                        f"{e6_stats['median']:.2f}",
                        f"{e6_stats['p90']:.2f}",
                        f"{e6_stats['p95']:.2f}",
                        f"{e6_stats['p99']:.2f}",
                        f"{e6_stats['min']:.2f}",
                        f"{e6_stats['max']:.2f}",
                    ])
                else:
                    row.extend(['', '', '', '', '', '', ''])

                # Databricks columns
                if dbr_stats:
                    row.extend([
                        f"{dbr_stats['avg']:.2f}",
                        f"{dbr_stats['median']:.2f}",
                        f"{dbr_stats['p90']:.2f}",
                        f"{dbr_stats['p95']:.2f}",
                        f"{dbr_stats['p99']:.2f}",
                        f"{dbr_stats['min']:.2f}",
                        f"{dbr_stats['max']:.2f}",
                    ])
                else:
                    row.extend(['', '', '', '', '', '', ''])

                # Difference columns
                if e6_stats and dbr_stats:
                    for metric in ['avg', 'median', 'p90', 'p95', 'p99', 'min', 'max']:
                        e6_val = e6_stats[metric]
                        dbr_val = dbr_stats[metric]
                        if dbr_val > 0:
                            diff = ((dbr_val - e6_val) / dbr_val) * 100
                            row.append(f"{diff:.1f}")
                        else:
                            row.append('')
                else:
                    row.extend(['', '', '', '', '', '', ''])

            writer.writerow(row)

        # Summary statistics
        writer.writerow([])
        writer.writerow(['SUMMARY STATISTICS'])

        for stat_label in ['Average', 'Median (p50)', 'p90', 'p95', 'p99', 'Min', 'Max']:
            row = [stat_label]

            for conc in all_concurrencies:
                # Collect E6Data values
                e6_values = []
                for key in data.keys():
                    if 'e6data' in key and conc in data[key]:
                        for query_stats in data[key][conc].values():
                            if stat_label == 'Average':
                                e6_values.append(query_stats['avg'])
                            elif stat_label == 'Median (p50)':
                                e6_values.append(query_stats['median'])
                            elif stat_label == 'p90':
                                e6_values.append(query_stats['p90'])
                            elif stat_label == 'p95':
                                e6_values.append(query_stats['p95'])
                            elif stat_label == 'p99':
                                e6_values.append(query_stats['p99'])
                            elif stat_label == 'Min':
                                e6_values.append(query_stats['min'])
                            elif stat_label == 'Max':
                                e6_values.append(query_stats['max'])

                # Collect Databricks values
                dbr_values = []
                for key in data.keys():
                    if 'databricks' in key and conc in data[key]:
                        for query_stats in data[key][conc].values():
                            if stat_label == 'Average':
                                dbr_values.append(query_stats['avg'])
                            elif stat_label == 'Median (p50)':
                                dbr_values.append(query_stats['median'])
                            elif stat_label == 'p90':
                                dbr_values.append(query_stats['p90'])
                            elif stat_label == 'p95':
                                dbr_values.append(query_stats['p95'])
                            elif stat_label == 'p99':
                                dbr_values.append(query_stats['p99'])
                            elif stat_label == 'Min':
                                dbr_values.append(query_stats['min'])
                            elif stat_label == 'Max':
                                dbr_values.append(query_stats['max'])

                # Calculate summary stats
                e6_summary = calculate_statistics(e6_values) if e6_values else None
                dbr_summary = calculate_statistics(dbr_values) if dbr_values else None

                # Get the appropriate metric
                metric_key = stat_label.split()[0].lower() if ' ' in stat_label else stat_label.lower()
                if '(' in metric_key:
                    metric_key = metric_key.split('(')[0].strip()

                if metric_key == 'median':
                    metric_key = 'median'
                elif metric_key not in ['avg', 'p90', 'p95', 'p99', 'min', 'max', 'median']:
                    metric_key = 'avg'

                # Add values
                if e6_summary:
                    row.extend([
                        f"{e6_summary[metric_key]:.2f}",
                        '', '', '', '', '', ''  # Placeholders for median, p90, p95, p99, min, max
                    ])
                else:
                    row.extend(['', '', '', '', '', '', ''])

                if dbr_summary:
                    row.extend([
                        f"{dbr_summary[metric_key]:.2f}",
                        '', '', '', '', '', ''  # Placeholders
                    ])
                else:
                    row.extend(['', '', '', '', '', '', ''])

                # Difference
                if e6_summary and dbr_summary:
                    e6_val = e6_summary[metric_key]
                    dbr_val = dbr_summary[metric_key]
                    if dbr_val > 0:
                        diff = ((dbr_val - e6_val) / dbr_val) * 100
                        row.append(f"{diff:.1f}")
                    else:
                        row.append('')
                    row.extend(['', '', '', '', '', ''])  # Placeholders
                else:
                    row.extend(['', '', '', '', '', '', ''])

            writer.writerow(row)

    print(f"\n✅ CSV generated: {output_file}", file=sys.stderr)
    print(f"   Queries analyzed: {len(all_queries)}", file=sys.stderr)
    print(f"   Concurrency levels: {', '.join(map(str, all_concurrencies))}", file=sys.stderr)


if __name__ == '__main__':
    main()
