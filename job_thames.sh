#!/bin/bash -l

#SBATCH --account=bddur64
#SBATCH --time=1:00:00
#SBATCH --job-name=THAMES
#SBATCH -o job_thames-%A_%a.out
#SBATCH -e job_thames-%A_%a.err
#SBATCH -N 1
##SBATCH -n 1
##SBATCH -c 1
#SBATCH --mem=8G

set -eo pipefail

# Select a partition at submission time, e.g. sbatch --partition=gpu ...
if [[ "${1:-}" == "--prepare" ]]; then
    if (( $# != 5 )); then
        echo "Usage: job_thames.sh --prepare {PARSEC|Ligra} <EPITONIC directory> <run directory> <prelude>" >&2
        exit 2
    fi
    suite=$2
    repo=$3
    run_dir=$4
    prelude=$5
    cd "$repo"
    trap 'status=$?; echo "$status" > "$run_dir/exit_code"' EXIT
    exec 9>runs/preparation.lock
    flock -n 9 || { echo "Another preparation job is running in this repository." >&2; exit 1; }
    if ! eval "$prelude"; then
        echo "Remote prelude failed." >&2
        exit 1
    fi
    case "$suite" in
        PARSEC|Ligra) ;;
        *) echo "Unsupported benchmark suite: $suite" >&2; exit 1 ;;
    esac
    thames="$repo/../THAMES"
    test -x "$thames/thames" || { echo "THAMES executable not found: $thames/thames" >&2; exit 1; }
    command -v python >/dev/null || { echo "Python not found on PATH" >&2; exit 1; }
    mkdir -p "$thames/Results"
    test -d "$thames/data/$suite" || { echo "Benchmark directory not found: $thames/data/$suite" >&2; exit 1; }
    export LC_ALL=C
    shopt -s nullglob
    files=()
    for csv in "$thames/data/$suite/"*.csv; do
        if [[ -f "$csv" && "$csv" != *_thermal_output.csv ]]; then
            files+=("$csv")
        fi
    done
    if (( ${#files[@]} == 0 )); then
        echo "No raw CSV files found in $thames/data/$suite." >&2
        exit 1
    fi
    for csv in "${files[@]}"; do
        prefix="${csv##*/}"
        prefix="${prefix%.csv}"
        echo "Preparing $csv"
        (cd "$thames" && ./thames "$csv" Results)
        python convert_thames_to_epitonic.py --prefix "$prefix" --results-dir "$thames/Results" --data-dir "$repo/data"
    done
    echo "Preparation complete."
    exit 0
fi

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"

# Sorted so task IDs map to the same file on every run
mapfile -t FILES < <(find data/Ligra -maxdepth 1 -name '*.csv' | sort)

CSV="${FILES[$SLURM_ARRAY_TASK_ID]}"

echo "Task $SLURM_ARRAY_TASK_ID: $CSV"

mkdir -p stats
NAME=$(basename "$CSV" .csv)

/usr/bin/time -o "stats/${NAME}.time" \
    -f "file=$CSV wall_s=%e user_s=%U sys_s=%S maxrss_kb=%M" \
    ./thames "$CSV"

echo "end of job"
