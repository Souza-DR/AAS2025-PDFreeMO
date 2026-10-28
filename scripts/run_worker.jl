"""
One process of a partitioned benchmark run (see `main` in `run_all_problems.jl`).

    julia --project=. scripts/run_worker.jl <assignment.tsv> <worker> <outdir> [nrun]

`assignment.tsv` holds one `<worker><TAB><problem>` line per problem of the
protocol (`#` starts a comment); `nworkers` is the number of distinct workers in
it. The worker generates the configurations of every protocol problem, solves
only its own and writes to `outdir`, which must not be shared with another
worker. `nrun` defaults to the protocol value (pilot runs pass a smaller one).
Before each problem the machine load, the logged-in users and the busiest
processes of other users are printed, so that interference shows in the log.
"""

include(joinpath(@__DIR__, "run_all_problems.jl"))

"""
    read_assignment(path)

Return the `Dict{Symbol, Int}` problem => worker read from the TSV file at `path`.

# Throws
- `ErrorException`: If a line is malformed or a problem appears twice.
"""
function read_assignment(path::AbstractString)
    assignment = Dict{Symbol, Int}()
    for line in eachline(path)
        line = strip(first(split(line, '#')))
        isempty(line) && continue
        fields = split(line, '\t')
        length(fields) == 2 || error("Malformed assignment line: $line")
        problem = Symbol(strip(fields[2]))
        haskey(assignment, problem) && error("Problem $problem assigned twice")
        assignment[problem] = parse(Int, fields[1])
    end
    return assignment
end

"""
    log_machine_state(problem)

Print a timestamp, `uptime`, `who` and the processes of other users using at
least 1% of a CPU. Failures of the shell commands are reported, not thrown.
"""
function log_machine_state(problem)
    me = get(ENV, "USER", "")
    cmd = """uptime; who; ps -eo user,pid,pcpu,etime,comm --sort=-pcpu --no-headers | awk -v me="$me" '\$1 != me && \$1 != "root" && \$3 >= 1'"""
    println("[machine-state] $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS")) problem=$problem")
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
    missing_problems = setdiff(PROBLEMS, keys(assignment))
    isempty(missing_problems) || error("Problems without a worker: $missing_problems")
    run_problems = [p for p in PROBLEMS if assignment[p] == worker]
    main(; nrun, outdir = args[3], run_problems, worker,
         nworkers = length(unique(values(assignment))), on_problem_start = log_machine_state)
end

worker_main(ARGS)
