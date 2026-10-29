#!/usr/bin/env bash
# Launch a partitioned benchmark run: one `run_worker.jl` process per worker of the
# assignment file, each pinned to one physical core, detached from the SSH session.
#
#   scripts/launch_partitioned.sh <label> <assignment.tsv> [nrun]
#
# Layout (RUN_ROOT = parent directory of this repository, e.g. /dev/shm/f5-<date>):
#   RUN_ROOT/{AAS2025-PDFreeMO,MOSolvers.jl,MultiObjectiveProblems.jl}  code
#   RUN_ROOT/julia-1.12.1, RUN_ROOT/depot                               Julia and depot
#   RUN_ROOT/results/<label>/worker_<k>/                                results of worker k
#   RUN_ROOT/results/<label>/logs/worker_<k>.log                        log of worker k
#   RUN_ROOT/results/<label>/{launch.txt,pids.txt,assignment.tsv}       run metadata
#
# Worker k runs on CPU k-1 (CPUS overrides the list, one CPU per worker in order).
# Environment overrides: JULIA, JULIA_DEPOT_PATH, CPUS, SNAPSHOT_DIR,
# SNAPSHOT_SECONDS (copy of results/<label> to SNAPSHOT_DIR/<label> every
# SNAPSHOT_SECONDS and once after the last worker ends, by scripts/snapshot_results.sh;
# 0 disables it; SNAPSHOT_DIR is meant to be a persistent home, e.g. NFS).
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <label> <assignment.tsv> [nrun]" >&2
    exit 1
fi
label=$1
assignment=$(realpath "$2")
nrun=${3:-}

repo=$(cd "$(dirname "$0")/.." && pwd)
run_root=$(dirname "$repo")
julia=${JULIA:-$run_root/julia-1.12.1/bin/julia}
# The bundled depot of the installation keeps the precompiled stdlibs; without it
# every stdlib is recompiled into the depot (REPL hung doing so on neuroniop).
export JULIA_DEPOT_PATH=${JULIA_DEPOT_PATH:-$run_root/depot:$(dirname "$(dirname "$julia")")/share/julia}
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export JULIA_PKG_OFFLINE=true  # the depot is already instantiated; never resolve during a run
snapshot_dir=${SNAPSHOT_DIR:-$HOME/f5-snapshots}
snapshot_seconds=${SNAPSHOT_SECONDS:-1800}

results=$run_root/results/$label
if [[ -e $results ]]; then
    echo "$results already exists; choose another label" >&2
    exit 1
fi

mapfile -t workers < <(grep -v '^[[:space:]]*#' "$assignment" | awk -F'\t' 'NF >= 2 {print $1}' | sort -n -u)
read -r -a cpus <<< "${CPUS:-$(seq -s ' ' 0 $((${#workers[@]} - 1)))}"
if [[ ${#cpus[@]} -lt ${#workers[@]} ]]; then
    echo "${#workers[@]} workers but only ${#cpus[@]} CPUs in CPUS" >&2
    exit 1
fi

mkdir -p "$results/logs"
cp "$assignment" "$results/assignment.tsv"
{
    echo "label: $label"
    echo "date: $(date --iso-8601=seconds)"
    echo "host: $(hostname)"
    echo "julia: $julia ($("$julia" --version))"
    echo "JULIA_DEPOT_PATH: $JULIA_DEPOT_PATH"
    echo "nrun: ${nrun:-protocol default}"
    echo "assignment: $assignment"
    for dir in "$repo" "$run_root/MOSolvers.jl" "$run_root/MultiObjectiveProblems.jl"; do
        echo "git $(basename "$dir"): $(git -C "$dir" rev-parse HEAD) dirty=[$(git -C "$dir" status --porcelain | tr '\n' ';')]"
    done
    echo "--- uptime / who / processes of other users at launch"
    uptime
    who
    ps -eo user,pid,pcpu,etime,comm --sort=-pcpu --no-headers | awk -v me="$USER" '$1 != me && $1 != "root" && $3 >= 1'
} > "$results/launch.txt"

cd "$repo"
for i in "${!workers[@]}"; do
    w=${workers[$i]}
    cpu=${cpus[$i]}
    out=$results/worker_$(printf '%02d' "$w")
    log=$results/logs/worker_$(printf '%02d' "$w").log
    # setsid + nohup: the worker survives the end of the SSH session.
    setsid nohup taskset -c "$cpu" "$julia" --project=. scripts/run_worker.jl \
        "$results/assignment.tsv" "$w" "$out" $nrun > "$log" 2>&1 < /dev/null &
    echo "worker=$w cpu=$cpu pid=$! log=$log" | tee -a "$results/pids.txt"
done

if [[ $snapshot_seconds -gt 0 ]]; then
    # Low-priority periodic copy out of RAM, plus a final one after the last worker ends.
    mapfile -t pids < <(awk '{sub("pid=", "", $3); print $3}' "$results/pids.txt")
    setsid nohup "$repo/scripts/snapshot_results.sh" "$results" "$snapshot_dir/$label" \
        "$snapshot_seconds" "${pids[@]}" > /dev/null 2>&1 < /dev/null &
    echo "snapshot pid=$! every ${snapshot_seconds}s to $snapshot_dir/$label" | tee -a "$results/pids.txt"
fi
