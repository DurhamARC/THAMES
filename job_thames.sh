#!/bin/bash

#SBATCH --account=bddur64
#SBATCH --time=23:00:00
#SBATCH --partition=infer          # Change to a CPU partition if your cluster has one
#SBATCH --job-name=THAMES
#SBATCH -o job_thames-%A_%a.out
#SBATCH -e job_thames-%A_%a.err
#SBATCH -N 1
##SBATCH -n 1
##SBATCH -c 1
#SBATCH --mem=8G

set -euo pipefail

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
