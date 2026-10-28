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

# PDFPM parameters, shared by both step tolerance rules so that only the rule differs
const PDFPM_SPECIFIC_OPTIONS = SolverSpecificOptions(
    max_subproblem_iter = 20, epsilon = 1e-4, sigma = 1.0, # Limit subproblem iterations for benchmarking
    # epsilon, sigma, alpha will otherwise use defaults
)

# Optional solver-specific parameters
const SOLVER_SPECIFIC_OPTIONS = Dict{Symbol, SolverSpecificOptions{Float64}}(
    :PDFPM => PDFPM_SPECIFIC_OPTIONS,
    :PDFPM_trace_scaled => PDFPM_SPECIFIC_OPTIONS,
    :ProxGrad => SolverSpecificOptions(
        mu = 1.0                    # Explicitly set default value
    )
    # :CondG => SolverSpecificOptions()  # No specific parameters; can be omitted
)

# Benchmark configuration
# :PDFPM and :PDFPM_trace_scaled differ only in PDFPM's step_tolerance_rule
# (:epsilon and :trace_scaled); :Dfree is PDFPM without evalJf, with :epsilon.
const SOLVERS = [:PDFPM, :PDFPM_trace_scaled, :Dfree, :ProxGrad, :CondG] # Solver identifiers
# const SOLVERS = [:PDFPM]
const NRUN = 200
const DELTAS = [0.0, 0.02, 0.05, 0.1]
# all_list = [Symbol(p) for p in sort(MultiObjectiveProblems.filter_problems(has_jacobian=true))]
all_list = [Symbol(p) for p in sort(MultiObjectiveProblems.get_problem_names())]
const PROBLEMS = all_list
const SEED = 42
println("Selected problems: $PROBLEMS")

"""
    main(; problems=PROBLEMS, solvers=SOLVERS, nrun=NRUN, deltas=DELTAS, outdir=datadir("sims"))

Run the full benchmark suite across all configured problems, solvers, and
perturbation levels. Results are saved under `outdir` with a timestamped
JLD2 file plus one file per problem in `outdir/problems`; each file carries
a provenance record per problem (see `collect_provenance`). The keywords exist
for smoke runs; the defaults are the experimental protocol.
"""
function main(; problems = PROBLEMS, solvers = SOLVERS, nrun = NRUN, deltas = DELTAS,
              outdir = datadir("sims"))
    Random.seed!(SEED)
    mkpath(outdir)
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    filename = "all_results_$(timestamp).jld2"
    filepath = joinpath(outdir, filename)


    println("Starting benchmark with $(length(problems)) problems")
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
        println("Total instances for problem $problem: $(length(configs))")

        # Execute with batch saving to reduce data loss risk
        results = AAS2025PDFreeMO.run_experiment_with_batch_saving(
            configs,
            batch_size=50,
            filename_base="$problem",
            outdir=outdir,
            provenance=AAS2025PDFreeMO.collect_provenance(configs; seed=SEED),
        )

        AAS2025PDFreeMO.append_from_jld2(filepath, joinpath(outdir, "$problem.jld2"))

        mkpath(joinpath(outdir, "problems"))
        mv(joinpath(outdir, "$problem.jld2"),
        joinpath(outdir, "problems", "$problem.jld2"); force=true)

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
