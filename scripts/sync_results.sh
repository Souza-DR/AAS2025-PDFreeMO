#!/usr/bin/env bash
# Pull the results of a remote partitioned run (see launch_partitioned.sh) to this
# machine with incremental rsync, every <interval> seconds, until the remote workers
# are gone; then one last pull. Run it on the local machine, e.g. with nohup.
#
#   scripts/sync_results.sh <remote_results_dir> <local_dir> [interval_seconds]
#
# Environment: REMOTE (default danilo@neuroniop), SSH_JUMP (default
# danilo@caruara.ime.unicamp.br:2022; empty for none).
# A JLD2 file copied while a worker appends to it can be torn; the next pull
# replaces it, and only the pull made after all workers ended is authoritative.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: $0 <remote_results_dir> <local_dir> [interval_seconds]" >&2
    exit 1
fi
remote_dir=${1%/}
local_dir=$2
interval=${3:-1800}
remote=${REMOTE:-danilo@neuroniop}
jump=${SSH_JUMP-danilo@caruara.ime.unicamp.br:2022}
ssh_cmd="ssh -o BatchMode=yes -o ServerAliveInterval=60${jump:+ -J $jump}"

mkdir -p "$local_dir"
log=$local_dir/sync.log

pull() {
    rsync -az --partial -e "$ssh_cmd" "$remote:$remote_dir/" "$local_dir/" \
        && echo "$(date --iso-8601=seconds) pull ok" >> "$log" \
        || echo "$(date --iso-8601=seconds) pull failed ($?)" >> "$log"
}

workers_alive() {
    # pids.txt lists the worker PIDs written by launch_partitioned.sh.
    $ssh_cmd "$remote" "pids=\$(grep '^worker=' '$remote_dir/pids.txt' | sed 's/.*pid=\([0-9]*\).*/\1/'); for p in \$pids; do kill -0 \$p 2>/dev/null && exit 0; done; exit 1"
}

while true; do
    pull
    status=0
    workers_alive || status=$?
    if [[ $status == 1 ]]; then
        sleep 60
        pull
        echo "$(date --iso-8601=seconds) no worker alive; final pull done" >> "$log"
        break
    elif [[ $status != 0 ]]; then
        # ssh itself failed (exit 255): keep trying at the next interval.
        echo "$(date --iso-8601=seconds) worker check failed ($status)" >> "$log"
    fi
    sleep "$interval"
done
