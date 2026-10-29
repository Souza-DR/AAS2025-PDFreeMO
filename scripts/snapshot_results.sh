#!/usr/bin/env bash
# Copy the results of a running partitioned run out of RAM (see launch_partitioned.sh),
# every <interval> seconds while a worker is alive, and once more after the last
# worker ends. The final copy starts only after every worker has exited, so it holds
# complete files; it is retried until it succeeds (at most 5 attempts).
#
#   scripts/snapshot_results.sh <results_dir> <snapshot_dir> <interval_seconds> <pid>...
#
# Environment: SNAPSHOT_POLL_SECONDS (default 60), how often the workers are checked.
# Each copy is appended to <results_dir>/logs/snapshot.log.
set -uo pipefail

if [[ $# -lt 4 ]]; then
    echo "usage: $0 <results_dir> <snapshot_dir> <interval_seconds> <pid>..." >&2
    exit 1
fi
results=${1%/}
dest=${2%/}
interval=$3
shift 3
pids=("$@")
poll=${SNAPSHOT_POLL_SECONDS:-60}
log=$results/logs/snapshot.log

copy() {
    mkdir -p "$dest" && nice -n 19 ionice -c3 rsync -a "$results/" "$dest/"
}

any_alive() {
    local p
    for p in "${pids[@]}"; do
        kill -0 "$p" 2>/dev/null && return 0
    done
    return 1
}

last=$(date +%s)
while any_alive; do
    sleep "$poll"
    now=$(date +%s)
    if (( now - last >= interval )) && any_alive; then
        if copy; then
            echo "$(date --iso-8601=seconds) snapshot ok" >> "$log"
        else
            echo "$(date --iso-8601=seconds) snapshot failed ($?)" >> "$log"
        fi
        last=$now
    fi
done

# Every worker has exited: their files are complete.
for attempt in 1 2 3 4 5; do
    if copy; then
        echo "$(date --iso-8601=seconds) final snapshot ok (no worker alive)" >> "$log"
        cp "$log" "$dest/logs/"  # so that the copy also records its own completion
        exit 0
    fi
    echo "$(date --iso-8601=seconds) final snapshot failed (attempt $attempt)" >> "$log"
    sleep "$poll"
done
exit 1
