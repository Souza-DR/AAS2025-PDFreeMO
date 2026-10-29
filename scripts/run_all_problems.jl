using DrWatson
using MultiObjectiveProblems
using MOSolvers
using Random
using Dates
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# --- CENTRALIZED SOLVER CONFIGURATION ---
# ========================================================================================

# Shared parameters applied to every solver configuration
const COMMON_SOLVER_OPTIONS = CommonSolverOptions(
    verbose = 1,                   # Keep output lean for benchmarking
    max_iter = 100,                # Maximum iterations
    opt_tol = 1e-4,                # Optimality tolerance
    ftol = 1e-4,                   # Function tolerance
    max_time = 3600.0,             # Maximum runtime in seconds
    print_interval = 1,            # Logging interval
    store_level = :low,            # Per-iteration Fval, abs_theta, progress (PDFPM: sigma, max tr B); no x_trace
    stop_criteria = :NormProgress
)

# PDFPM parameters, shared by both step tolerance rules and by :Dfree so that only
# the rule or the presence of the Jacobian differs
const PDFPM_SPECIFIC_OPTIONS = SolverSpecificOptions(
    max_subproblem_iter = 20, epsilon = 1e-4, sigma = 1.0, # Limit subproblem iterations for benchmarking
    # epsilon, sigma, alpha will otherwise use defaults
)

# Optional solver-specific parameters
const SOLVER_SPECIFIC_OPTIONS = Dict{Symbol, SolverSpecificOptions{Float64}}(
    :PDFPM => PDFPM_SPECIFIC_OPTIONS,
    :PDFPM_trace_scaled => PDFPM_SPECIFIC_OPTIONS,
    :Dfree => PDFPM_SPECIFIC_OPTIONS,
    :ProxGrad => SolverSpecificOptions(
        mu = 1.0                    # Explicitly set default value
    )
    # :CondG => SolverSpecificOptions()  # No specific parameters; can be omitted
)

# Benchmark configuration
# :PDFPM and :PDFPM_trace_scaled differ only in PDFPM's step_tolerance_rule
# (:epsilon and :trace_scaled). :Dfree (PDFPM without evalJf, with :epsilon) is
# still supported by the runner but runs in a separate finite-difference
# experiment, so it is not in the default list.
const SOLVERS = [:PDFPM, :PDFPM_trace_scaled, :ProxGrad, :CondG] # Solver identifiers
# const SOLVERS = [:PDFPM]
const NRUN = 200
const DELTAS = [0.0, 0.02, 0.05, 0.1]
# all_list = [Symbol(p) for p in sort(MultiObjectiveProblems.filter_problems(has_jacobian=true))]
all_list = [Symbol(p) for p in sort(MultiObjectiveProblems.get_problem_names())]
const PROBLEMS = all_list
const SEED = 42
println("Selected problems: $PROBLEMS")

"""
    main(; problems=PROBLEMS, solvers=SOLVERS, nrun=NRUN, deltas=DELTAS, outdir=datadir("sims"),
         run_problems=problems, run_deltas=Dict(), worker=1, nworkers=1, on_problem_start=nothing)

Run the full benchmark suite across all configured problems, solvers, and
perturbation levels. Results are saved under `outdir` with a timestamped
JLD2 file plus one file per problem in `outdir/problems`; each file carries
a provenance record per problem (see `collect_provenance`). The keywords exist
for smoke runs and for partitioned runs; the defaults are the experimental protocol.

# Partitioned runs
The configurations of every problem in `problems` are generated in order, so the
random stream (initial points and `A` matrices) is the one of the sequential run,
but only the problems in `run_problems` are solved. `run_deltas[problem]`, when
present, restricts the solved deltas of that problem (the others are generated
and skipped, so the draws do not change); such a part is saved as
`<problem>_delta_<δ>…` (see `part_name`) and its provenance record lists the
solved `deltas` next to the `protocol_deltas`. Each of `nworkers` processes
passes its own `run_problems`, `run_deltas`, `worker` and `outdir`; no file is
shared. The partition (`worker`, `nworkers`, `run_problems`, `run_deltas`,
`problems`) is stored in the provenance record under `"partition"`.
`on_problem_start(problem, deltas)`, if given, is called before a problem is
solved with the deltas to solve (e.g. to log the machine load).

# Compilation
Before the measured runs of each problem, run 1 of each (solver, solved delta)
is run and discarded (see `warm_up`), so that no `total_time` includes
compilation; each result records its own `compile_time` as proof. The warm-up
is logged as `[warmup]` and stored in the provenance record under `"warmup"`.
The provenance is collected before the warm-up, and the JLD2 writes of the run
are rehearsed once per process before the first warm-up (see `rehearse_result_io`).

# Throws
- `ArgumentError`: If `run_problems` holds a problem that is not in `problems`,
  or `run_deltas` a problem not in `run_problems` or a delta not in `deltas`.
"""
function main(; problems = PROBLEMS, solvers = SOLVERS, nrun = NRUN, deltas = DELTAS,
              outdir = datadir("sims"), run_problems = problems, run_deltas = Dict(),
              worker = 1, nworkers = 1, on_problem_start = nothing)
    problems = Symbol.(problems)
    run_problems = Symbol.(run_problems)
    unknown = setdiff(run_problems, problems)
    isempty(unknown) || throw(ArgumentError("run_problems not in problems: $unknown"))
    run_deltas = Dict(Symbol(problem) => collect(ds) for (problem, ds) in run_deltas)
    for (problem, ds) in run_deltas
        problem in run_problems || throw(ArgumentError("run_deltas has $problem, which is not in run_problems"))
        # Exact match: a delta is a protocol value, never a measured one.
        bad = filter(d -> !any(isequal(d), deltas), ds)
        (isempty(ds) || !isempty(bad)) && throw(ArgumentError("run_deltas[$problem] = $ds must be a nonempty subset of $deltas"))
    end
    partition = Dict{String, Any}("worker" => worker, "nworkers" => nworkers,
                                  "run_problems" => string.(run_problems),
                                  "run_deltas" => Dict{String, Any}(string(p) => ds for (p, ds) in run_deltas),
                                  "problems" => string.(problems))

    Random.seed!(SEED)
    mkpath(outdir)
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    filename = "all_results_$(timestamp).jld2"
    filepath = joinpath(outdir, filename)


    io_rehearsed = false
    println("Starting benchmark with $(length(problems)) problems")
    println("Worker $worker of $nworkers: $(length(run_problems)) problems to solve")
    println("Solvers: $(length(solvers)), Runs: $nrun, Deltas: $deltas")
    println("Common options: max_iter=$(COMMON_SOLVER_OPTIONS.max_iter), opt_tol=$(COMMON_SOLVER_OPTIONS.opt_tol)")

    for problem in problems
        # Generate experiment configurations with standardized options
        configs = AAS2025PDFreeMO.generate_experiment_configs(
            [Symbol(problem)],
            solvers,
            nrun,
            deltas,
            COMMON_SOLVER_OPTIONS;
            solver_specific_options = SOLVER_SPECIFIC_OPTIONS
        )
        # The draws above are made for every problem and delta; solving and saving
        # do not touch the global stream, so skipping a problem or a delta keeps
        # the next draws.
        problem in run_problems || continue
        solve_deltas = [d for d in deltas if any(isequal(d), get(run_deltas, problem, deltas))]
        configs = filter(config -> any(isequal(config.delta), solve_deltas), configs)
        part = AAS2025PDFreeMO.part_name(problem, solve_deltas, deltas)
        println("Total instances for $part: $(length(configs))")
        isnothing(on_problem_start) || on_problem_start(problem, solve_deltas)
        start_time = time()

        # Collected before the warm-up, and the JLD2 writes rehearsed once per process:
        # code compiled between the warm-up and the measured runs can invalidate the
        # solvers' compiled code (see `rehearse_result_io`).
        provenance = merge(AAS2025PDFreeMO.collect_provenance(configs; seed=SEED, protocol_deltas=deltas),
                           Dict{String, Any}("partition" => partition))
        if !io_rehearsed
            AAS2025PDFreeMO.rehearse_result_io(configs, provenance, outdir)
            io_rehearsed = true
        end
        warmup = AAS2025PDFreeMO.warm_up(configs)
        println("[warmup] worker=$worker problem=$problem deltas=$(join(solve_deltas, ",")) runs=$(length(warmup["runs"])) seconds=$(round(warmup["seconds"]; digits=3)) compile_seconds=$(round(warmup["compile_seconds"]; digits=3))")

        # Execute with batch saving to reduce data loss risk
        results = AAS2025PDFreeMO.run_experiment_with_batch_saving(
            configs,
            batch_size=50,
            filename_base=part,
            outdir=outdir,
            provenance=merge(provenance, Dict{String, Any}("warmup" => warmup)),
        )

        AAS2025PDFreeMO.append_from_jld2(filepath, joinpath(outdir, "$part.jld2"))

        mkpath(joinpath(outdir, "problems"))
        mv(joinpath(outdir, "$part.jld2"),
        joinpath(outdir, "problems", "$part.jld2"); force=true)
        println("[problem-time] worker=$worker problem=$problem deltas=$(join(solve_deltas, ",")) seconds=$(round(time() - start_time; digits=3))")

        # --- manual memory cleanup ---
        configs = nothing
        results = nothing
        GC.gc()

        println("\nBenchmark completed! Results saved in: $outdir")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
