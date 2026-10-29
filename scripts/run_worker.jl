"""
One process of a partitioned benchmark run (see `main` in `run_all_problems.jl`).

    julia --project=. scripts/run_worker.jl <assignment.tsv> <worker> <outdir> [nrun]

`assignment.tsv` assigns every (problem, delta) of the protocol to a worker
(`#` starts a comment): a `<worker><TAB><problem>` line assigns all deltas of the
problem, `<worker><TAB><problem><TAB><delta>` lines split it by delta (see
`read_assignment`); `nworkers` is the number of distinct workers in it. The
worker generates the configurations of every protocol problem and delta, solves
only its own and writes to `outdir`, which must not be shared with another
worker. `nrun` defaults to the protocol value (pilot runs pass a smaller one).
Before each problem the machine load, the logged-in users and the busiest
processes of other users are printed, so that interference shows in the log.
"""

include(joinpath(@__DIR__, "run_all_problems.jl"))

"""
    read_assignment(path; problems=PROBLEMS, deltas=DELTAS)

Return the `Dict{Tuple{Symbol, Float64}, Int}` (problem, delta) => worker read
from the TSV file at `path`. A `<worker><TAB><problem>` line assigns every delta
of the problem; a `<worker><TAB><problem><TAB><delta>` line assigns one delta,
which must be one of `deltas` exactly (no tolerance). A problem is given either
by one whole line or by delta lines, never both.

# Throws
- `ErrorException`: If a line is malformed, names a problem not in `problems` or
  a delta not in `deltas`, mixes a whole line and delta lines of one problem,
  assigns a (problem, delta) twice, or leaves one without a worker.
"""
function read_assignment(path::AbstractString; problems = PROBLEMS, deltas = DELTAS)
    assignment = Dict{Tuple{Symbol, Float64}, Int}()
    whole, by_delta = Set{Symbol}(), Set{Symbol}()
    for line in eachline(path)
        line = strip(first(split(line, '#')))
        isempty(line) && continue
        fields = strip.(split(line, '\t'))
        length(fields) in (2, 3) || error("Malformed assignment line: $line")
        worker = parse(Int, fields[1])
        problem = Symbol(fields[2])
        problem in problems || error("Problem $problem is not in the protocol: $line")
        if length(fields) == 2
            problem in by_delta && error("Problem $problem has a whole line and delta lines")
            push!(whole, problem)
            line_deltas = deltas
        else
            delta = parse(Float64, fields[3])
            any(isequal(delta), deltas) || error("Delta $delta of $problem is not in $deltas")
            problem in whole && error("Problem $problem has a whole line and delta lines")
            push!(by_delta, problem)
            line_deltas = [delta]
        end
        for delta in line_deltas
            haskey(assignment, (problem, delta)) && error("($problem, $delta) assigned twice")
            assignment[(problem, delta)] = worker
        end
    end
    unassigned = [(p, d) for p in problems for d in deltas if !haskey(assignment, (p, d))]
    isempty(unassigned) || error("(problem, delta) without a worker: $unassigned")
    return assignment
end

"""
    log_machine_state(problem, deltas)

Print a timestamp, the problem and its deltas to solve, `uptime`, `who` and the processes of other users using at
least 1% of a CPU. Failures of the shell commands are reported, not thrown.
"""
function log_machine_state(problem, deltas)
    me = get(ENV, "USER", "")
    cmd = """uptime; who; ps -eo user,pid,pcpu,etime,comm --sort=-pcpu --no-headers | awk -v me="$me" '\$1 != me && \$1 != "root" && \$3 >= 1'"""
    println("[machine-state] $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS")) problem=$problem deltas=$(join(deltas, ","))")
    flush(stdout)  # the shell commands write to the same file descriptor
    try
        run(`sh -c $cmd`)
    catch e
        println("[machine-state] failed: ", sprint(showerror, e))
    end
    flush(stdout)
end

function worker_main(args)
    length(args) in (3, 4) || error("usage: run_worker.jl <assignment.tsv> <worker> <outdir> [nrun]")
    assignment = read_assignment(args[1])
    worker = parse(Int, args[2])
    nrun = length(args) == 4 ? parse(Int, args[4]) : NRUN
    mine = [(p, d) for p in PROBLEMS for d in DELTAS if assignment[(p, d)] == worker]
    run_problems = unique(first.(mine))
    run_deltas = Dict(p => [d for (q, d) in mine if q == p] for p in run_problems)
    main(; nrun, outdir = args[3], run_problems, run_deltas, worker,
         nworkers = length(unique(values(assignment))), on_problem_start = log_machine_state)
end

worker_main(ARGS)
