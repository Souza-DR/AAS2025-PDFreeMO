using DrWatson
using MOProblems
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
    store_trace = false,           # Avoid trace storage to conserve memory
    stop_criteria = :NormProgress
)

# Optional solver-specific parameters
const SOLVER_SPECIFIC_OPTIONS = Dict{Symbol, SolverSpecificOptions{Float64}}(
    :PDFPM => SolverSpecificOptions(
        max_subproblem_iter = 20, epsilon = 1e-4, sigma = 1.0, # Limit subproblem iterations for benchmarking
        # epsilon, sigma, alpha will otherwise use defaults
    ),
    :ProxGrad => SolverSpecificOptions(
        mu = 1.0                    # Explicitly set default value
    )
    # :CondG => SolverSpecificOptions()  # No specific parameters; can be omitted
)

# Benchmark configuration
const SOLVERS = [:PDFPM, :Dfree, :ProxGrad, :CondG] # Solver identifiers
# const SOLVERS = [:PDFPM]
const NRUN = 200
const DELTAS = [0.0, 0.02, 0.05, 0.1]
# all_list = [Symbol(p) for p in sort(MOProblems.filter_problems(has_jacobian=true))]
all_list = [Symbol(p) for p in sort(MOProblems.get_problem_names())]
const PROBLEMS = all_list
println("Selected problems: $PROBLEMS")

"""
Run the full benchmark suite across all configured problems, solvers, and
perturbation levels. Results are saved under `datadir("sims")` with a timestamped
JLD2 file plus one file per problem.
"""
function main()
    Random.seed!(42)
    mkpath(datadir("sims"))
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    filename = "all_results_$(timestamp).jld2"
    filepath = joinpath(datadir("sims"), filename)


    println("Starting benchmark with $(length(PROBLEMS)) problems")
    println("Solvers: $(length(SOLVERS)), Runs: $NRUN, Deltas: $DELTAS")
    println("Common options: max_iter=$(COMMON_SOLVER_OPTIONS.max_iter), opt_tol=$(COMMON_SOLVER_OPTIONS.opt_tol)")

    for problem in PROBLEMS
        # Generate experiment configurations with standardized options
        configs = AAS2025PDFreeMO.generate_experiment_configs(
            [Symbol(problem)], 
            SOLVERS, 
            NRUN, 
            DELTAS, 
            COMMON_SOLVER_OPTIONS;
            solver_specific_options = SOLVER_SPECIFIC_OPTIONS
        )
        println("Total instances for problem $problem: $(length(configs))")

        # Execute with batch saving to reduce data loss risk
        results = AAS2025PDFreeMO.run_experiment_with_batch_saving(
            configs,
            batch_size=50,
            filename_base="$problem",
        )

        AAS2025PDFreeMO.append_from_jld2(filepath, joinpath(datadir("sims"), "$problem.jld2"))

        mkpath(joinpath(datadir("sims"), "problems"))
        mv(joinpath(datadir("sims"), "$problem.jld2"),
        joinpath(datadir("sims"), "problems", "$problem.jld2"); force=true)

        # --- manual memory cleanup ---
        configs = nothing
        results = nothing
        GC.gc()

        println("\nBenchmark completed! Results saved in: $(datadir("sims"))")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
