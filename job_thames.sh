#!/bin/bash -l

#SBATCH --account=bddur64
#SBATCH --time=6:00:00
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
    total_files=${#files[@]}
    counts=()
    total_timesteps=0
    for csv in "${files[@]}"; do
        count=$(cd "$thames" && ./thames --count-timesteps "$csv") || {
            echo "Could not count timesteps in $csv; ensure THAMES is rebuilt with progress support." >&2
            exit 1
        }
        [[ "$count" =~ ^[1-9][0-9]*$ ]] || {
            echo "Invalid timestep count for $csv: $count" >&2
            exit 1
        }
        counts+=("$count")
        total_timesteps=$((total_timesteps + count))
    done
    progress_file="$run_dir/thames_progress.json"
    if [[ "$run_dir" == /* ]]; then
        timestep_file="$run_dir/thames_timestep_progress"
    else
        timestep_file="$PWD/$run_dir/thames_timestep_progress"
    fi
    update_progress() {
        python - "$progress_file" "$total_files" "$total_timesteps" "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import json
import os
import sys

path, total, total_steps, completed, current, action, completed_steps, current_steps = sys.argv[1:]
if action == "init":
    files = []
else:
    with open(path, encoding="utf-8") as source:
        files = json.load(source)["files"]
    if action == "start":
        files.append({"name": current, "status": "processing"})
    elif action == "complete":
        files[-1]["status"] = "completed"
progress = {
    "total": int(total),
    "completed": int(completed),
    "current": current if action == "start" else None,
    "files": files,
    "total_timesteps": int(total_steps),
    "completed_timesteps": int(completed_steps),
    "current_timesteps": int(current_steps),
}
temporary = path + ".tmp"
with open(temporary, "w", encoding="utf-8") as output:
    json.dump(progress, output)
    output.write("\n")
os.replace(temporary, path)
PYEOF
    }

    completed=0
    completed_steps=0
    update_progress "$completed" "" init "$completed_steps" 0
    for csv in "${files[@]}"; do
        current_steps=${counts[$completed]}
        prefix="${csv##*/}"
        prefix="${prefix%.csv}"
        echo "Preparing $csv"
        update_progress "$completed" "$prefix" start "$completed_steps" "$current_steps"
        (cd "$thames" && THAMES_TIMESTEP_PROGRESS="$timestep_file" \
            THAMES_PROGRESS_INDEX="$completed" THAMES_EXPECTED_TIMESTEPS="$current_steps" \
            ./thames "$csv" Results)
        if [[ ! -f "$timestep_file" ]] || [[ "$(cat "$timestep_file")" != "$completed $current_steps" ]]; then
            echo "THAMES did not report completed timesteps for $csv." >&2
            exit 1
        fi
        python convert_thames_to_epitonic.py --prefix "$prefix" --results-dir "$thames/Results" --data-dir "$repo/data"
        completed=$((completed + 1))
        completed_steps=$((completed_steps + current_steps))
        update_progress "$completed" "$prefix" complete "$completed_steps" 0
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
