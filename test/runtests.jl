# Tests of the compile-time record, the warm-up and the exclusion of compiled
# instances from the time profiles.
#
# Run in a new process, from the repository root:
#     julia --project=. test/runtests.jl
# The first test needs a solver call that this process has not compiled yet.

using Test
using Random
using JLD2
include(joinpath(@__DIR__, "..", "scripts", "run_all_problems.jl"))

quiet(f) = redirect_stdout(f, devnull)

problem_configs(problem; nrun = 2, deltas = [0.0, 0.02]) =
    generate_experiment_configs([problem], SOLVERS, nrun, deltas, COMMON_SOLVER_OPTIONS;
                                solver_specific_options = SOLVER_SPECIFIC_OPTIONS)

# Same field order as `ExperimentResult`; only what the analysis reads varies.
function fake_result(solver, problem, delta, run_id; iter, total_time, compile_time)
    return ExperimentResult{Float64}(solver, :none, problem, run_id, delta, [0.0], true, :converged, "",
                                     iter, 1, 1, total_time, compile_time, [0.0], [0.0],
                                     Vector{Float64}[], Vector{Float64}[], Float64[], Float64[], Float64[], Float64[])
end

# A result type without `compile_time`, as in files written before it existed.
struct ResultWithoutCompileTime
    converged::Bool
    iter::Int
    total_time::Float64
end

@testset "compile_time" begin
    Random.seed!(SEED)
    config = first(problem_configs(:AP1))
    cold = quiet(() -> AAS2025PDFreeMO.run_single_experiment(config))
    @test cold.status != :runner_error
    @test cold.compile_time > 0  # first solver call of the process
    again = quiet(() -> AAS2025PDFreeMO.run_single_experiment(config))
    @test again.compile_time == 0
    @test isequal(again.final_objective_value, cold.final_objective_value)

    # Timing is on during the measurement whatever the state of the counter, which
    # is restored afterwards: off (0), on elsewhere (1), and after an unpaired
    # switch-off (255, where a single switch-on would leave timing off).
    timing_counter = cglobal(:jl_measure_compile_time_enabled, UInt8)
    elapsed = Ref(-1.0)
    for (k, unpaired) in enumerate((nothing, true, false))
        isnothing(unpaired) || Base.cumulative_compile_timing(unpaired)
        counter = unsafe_load(timing_counter)
        fresh = eval(:(x -> sum(abs2, x .+ $k)))
        AAS2025PDFreeMO.with_compile_time(() -> Base.invokelatest(fresh, rand(3)), elapsed)
        @test elapsed[] > 0
        @test unsafe_load(timing_counter) == counter
        isnothing(unpaired) || Base.cumulative_compile_timing(!unpaired)
    end
    @test unsafe_load(timing_counter) == 0

    # Recorded when the call throws.
    elapsed[] = -1.0
    fresh = eval(:(x -> prod(x .* 4)))
    @test_throws ErrorException AAS2025PDFreeMO.with_compile_time(elapsed) do
        Base.invokelatest(fresh, rand(3))
        error("solver failure")
    end
    @test elapsed[] > 0
end

@testset "warm_up" begin
    Random.seed!(SEED)
    configs = problem_configs(:AP2)  # not solved before in this process; delta 0.02 never solved
    inputs = deepcopy([(config.initial_point, config.data_matrices) for config in configs])
    rng = copy(Random.default_rng())
    summary = quiet(() -> warm_up(configs))
    @test rng == Random.default_rng()
    @test isequal(inputs, [(config.initial_point, config.data_matrices) for config in configs])
    @test summary["policy"] == AAS2025PDFreeMO.WARMUP_POLICY
    @test sort([(run["solver"], run["delta"]) for run in summary["runs"]]) ==
          sort([(string(solver), delta) for solver in SOLVERS for delta in [0.0, 0.02]])
    @test summary["compile_seconds"] > 0

    measured = quiet(() -> [AAS2025PDFreeMO.run_single_experiment(config) for config in configs])
    @test all(result -> result.compile_time == 0, measured)
end

@testset "time profile excludes compiled instances" begin
    mktempdir() do dir
        file = joinpath(dir, "results.jld2")
        jldopen(file, "w") do f
            for solver in (:PDFPM, :CondG), run_id in 1:3
                compiled = solver == :CondG && run_id == 2
                f["$solver/AP1/delta_0-0/run_$run_id"] =
                    fake_result(solver, :AP1, 0.0, run_id; iter = 10 + run_id, total_time = 1.0 + run_id,
                                compile_time = compiled ? 0.5 : 0.0)
            end
        end
        solvers = ["PDFPM", "CondG"]
        times, rows = quiet(() -> extract_performance_data(file, "total_time", solvers))
        @test rows == [("AP1", 0.0, 1), ("AP1", 0.0, 3)]  # run 2 leaves for both solvers
        @test times == [2.0 2.0; 4.0 4.0]
        iters, rows = quiet(() -> extract_performance_data(file, "iter", solvers))
        @test length(rows) == 3
        times, rows = quiet(() -> extract_performance_data(file, "total_time", solvers; exclude_compiled = false))
        @test length(rows) == 3

        old = joinpath(dir, "old.jld2")
        jldopen(old, "w") do f
            f["PDFPM/AP1/delta_0-0/run_1"] = ResultWithoutCompileTime(true, 5, 0.3)
        end
        times, rows = @test_logs (:warn, r"no compile_time") quiet(() -> extract_performance_data(old, "total_time", ["PDFPM"]))
        @test times == fill(0.3, 1, 1)
    end
end
