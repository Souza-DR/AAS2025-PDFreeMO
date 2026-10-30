# Tests of the compile-time record, the warm-up, the exclusion of compiled
# instances from the time profiles, the final point and the stationarity merit w₁.
#
# Run in a new process, from the repository root:
#     julia --project=. test/runtests.jl
# The first test needs a solver call that this process has not compiled yet.

using Test
using Random
using JLD2
using LinearAlgebra: norm
include(joinpath(@__DIR__, "..", "scripts", "run_all_problems.jl"))

quiet(f) = redirect_stdout(f, devnull)

problem_configs(problem; nrun = 2, deltas = [0.0, 0.02]) =
    generate_experiment_configs([problem], SOLVERS, nrun, deltas, COMMON_SOLVER_OPTIONS;
                                solver_specific_options = SOLVER_SPECIFIC_OPTIONS)

# Same field order as `ExperimentResult`; only what the analysis reads varies.
function fake_result(solver, problem, delta, run_id; iter, total_time, compile_time, converged = true)
    return ExperimentResult{Float64}(solver, :none, problem, run_id, delta, [0.0], converged, :converged, "",
                                     iter, 1, 1, total_time, compile_time, [0.0], [0.0], [0.0],
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

@testset "rehearse_result_io" begin
    Random.seed!(SEED)
    configs = problem_configs(:AP3; nrun = 1, deltas = [0.0])
    provenance = AAS2025PDFreeMO.collect_provenance(configs; seed = SEED)
    mktempdir() do dir
        rng = copy(Random.default_rng())
        @test isnothing(AAS2025PDFreeMO.rehearse_result_io(configs, provenance, dir))
        @test rng == Random.default_rng()
        @test isempty(readdir(dir))  # nothing is left behind
    end
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

@testset "final_point" begin
    Random.seed!(SEED)
    for config in problem_configs(:AP1; nrun = 1)
        result = quiet(() -> AAS2025PDFreeMO.run_single_experiment(config))
        @test result.status != :runner_error
        @test length(result.final_point) == length(config.initial_point)
        if config.delta == 0  # F = f, evaluated by the solver at the returned point
            problem = MultiObjectiveProblems.AP1()
            @test MultiObjectiveProblems.eval_f(problem, result.final_point) ≈ result.final_objective_value rtol = 1e-14
        end
    end

    # Empty for :runner_error: the Jacobian of ZDT1 is undefined at x₁ = 0.
    config = first(problem_configs(:ZDT1; nrun = 1, deltas = [0.0]))
    config.initial_point[1] = 0.0
    result = quiet(() -> AAS2025PDFreeMO.run_single_experiment(config))
    @test result.status == :runner_error && occursin("DomainError", result.message)
    @test isempty(result.final_point)
end

# fⱼ(x) = ½‖x - cⱼ‖², so ∇fⱼ(x) = x - cⱼ; box [-10, 10]². With no active bound and
# h = 0, w₁(x) = ½ min_λ ‖Σ λⱼ ∇fⱼ(x)‖², the squared distance from 0 to the convex
# hull of the gradients, halved.
quadratic_jacobian(x, centers) = permutedims(reduce(hcat, [x - c for c in centers]))

@testset "merit w₁: closed form and stationary point" begin
    lb, ub = fill(-10.0, 2), fill(10.0, 2)
    for (centers, x, w1) in (
            # m = 2: gradients (6, 0) and (2, 0); λ = (0, 1); y = (1, 0)
            ([[0.0, 0.0], [4.0, 0.0]], [6.0, 0.0], 2.0),
            # m = 3: gradients (3, 3), (1, 3), (3, 1); midpoint of the last two, (2, 2); y = (1, 1)
            ([[0.0, 0.0], [2.0, 0.0], [0.0, 2.0]], [3.0, 3.0], 4.0),
            # Pareto critical: x in the convex hull of the centers
            ([[0.0, 0.0], [4.0, 0.0]], [1.0, 0.0], 0.0),
            ([[0.0, 0.0], [2.0, 0.0], [0.0, 2.0]], [0.5, 0.5], 0.0))
        Jf = quadratic_jacobian(x, centers)
        params = merit_params([rand(2, 2) for _ in centers], 0.0, lb, ub)
        r = merit_w1(x, Jf, params)
        @test r.success && r.tol == first(MERIT_TOLS)
        @test r.w1 ≈ w1 atol = 1e-10
        @test r.primal <= r.w1 + 1e-10
        @test r.primal ≈ w1 atol = 1e-10
        @test merit_w1_dual(x, Jf, lb, ub).w1 ≈ w1 atol = 1e-14
        w1 > 0 && @test r.y ≈ x - (w1 == 2.0 ? [2.0, 0.0] : [2.0, 2.0]) atol = 1e-6
    end

    # δ > 0: away from stationarity w₁ > 0, and the primal value is a lower bound.
    centers = [[0.0, 0.0], [4.0, 0.0]]
    params = merit_params([[2.0 0.5; 0.3 1.0], [1.0 0.2; 0.1 3.0]], 0.05, lb, ub)
    r = merit_w1([6.0, 1.0], quadratic_jacobian([6.0, 1.0], centers), params)
    @test r.success && r.w1 > 1 && !r.h_dropped
    @test r.primal <= r.w1 + 1e-10 && r.w1 - r.primal < 1e-9
    # h(x) given in closed form, δ‖A_j⁻ᵀx‖₁, instead of evalh!
    exact = [0.05 * norm(Aj' \ [6.0, 1.0], 1) for Aj in ([2.0 0.5; 0.3 1.0], [1.0 0.2; 0.1 3.0])]
    @test r.hx ≈ exact rtol = 1e-6
    given = merit_w1([6.0, 1.0], quadratic_jacobian([6.0, 1.0], centers), params; hx = exact)
    @test given.success && given.hx == exact
    @test given.w1 ≈ r.w1 atol = 1e-6
    MOSolvers.clear_evalh_cache!()
end

@testset "merit w₁: Ipopt × dual at δ = 0" begin
    Random.seed!(7)
    for name in (:BK1, :JOS1, :DTLZ2)  # m = 2, 2, 3
        problem = getfield(MultiObjectiveProblems, name)()
        lb, ub = MultiObjectiveProblems.recommended_bounds(problem)
        n, m = problem.nvar, problem.nobj
        params = merit_params([zeros(n, n) for _ in 1:m], 0.0, lb, ub)
        points = [lb + rand(n) .* (ub - lb) for _ in 1:4]
        # Points near stationarity, where the merit decides the thresholds
        for x0 in copy(points)
            run = ProxGrad(x -> MultiObjectiveProblems.eval_f(problem, x),
                           x -> MultiObjectiveProblems.eval_jacobian(problem, x),
                           [zeros(n, n) for _ in 1:m], 0.0, x0, ProxGrad_options(verbose = 0, opt_tol = 1e-8);
                           lb, ub)
            push!(points, run.x)
        end
        for x in points
            Jf = MultiObjectiveProblems.eval_jacobian(problem, x)
            r = merit_w1(x, Jf, params)
            dual = merit_w1_dual(x, Jf, lb, ub).w1
            @test r.success
            @test abs(r.w1 - dual) < 1e-10 * max(1, dual)
            @test r.primal <= dual * (1 + 1e-14) + 1e-300  # weak duality
        end
    end
    @test_throws ArgumentError merit_w1_dual(zeros(2), zeros(4, 2), fill(-1.0, 2), ones(2))
end

@testset "performance data: success criterion" begin
    mktempdir() do dir
        file = joinpath(dir, "results.jld2")
        jldopen(file, "w") do f
            for solver in (:PDFPM, :CondG), run_id in 1:3
                f["$solver/AP1/delta_0-0/run_$run_id"] =
                    fake_result(solver, :AP1, 0.0, run_id; iter = 10 * run_id, total_time = 1.0, compile_time = 0.0,
                                converged = !(solver == :CondG && run_id == 2))
            end
        end
        solvers = ["PDFPM", "CondG"]
        default = quiet(() -> extract_performance_data(file, "iter", solvers))
        explicit = quiet(() -> extract_performance_data(file, "iter", solvers; success = run_converged))
        @test isequal(default, explicit)
        @test isequal(default[1], [10.0 10.0; 20.0 NaN; 30.0 30.0])
        # Another criterion replaces the solver's own
        by_iter = quiet(() -> extract_performance_data(file, "iter", solvers; success = r -> r.iter >= 20))
        @test isequal(by_iter[1], [NaN NaN; 20.0 20.0; 30.0 30.0])
    end
end
