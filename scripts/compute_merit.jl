"""
Compute the stationarity merit w₁ (see `src/merit.jl`) at the returned point of
every run of a results file, and at every initial point.

    julia --project=. scripts/compute_merit.jl <results.jld2> <output.jld2> [problem ...]
    julia --project=. scripts/compute_merit.jl --join <output.jld2> <part.jld2> ...

The first form reads `results.jld2` (a merged file of `merge_partitioned.jl`,
whose results have `final_point`) and writes the table to `output.jld2`, which
must not exist; listing problems restricts the table to them, so that one
process per problem (or group of problems) can run in parallel. The second form
joins such parts into one table.

The `A` matrices and the initial points are not stored with the results: they
are regenerated as in the run (seed, problem order, `nrun` and protocol deltas
read from the provenance records of `results.jld2`), and every regenerated
initial point is checked against the stored one. Draws do not depend on the
solver list, so one solver is generated.

Each row is a named tuple with `solver` (`:x0` for an initial point), `problem`,
`delta`, `run_id`, `status`, `w1`, `sqrt_2w1` (√(2 max(w₁, 0))), `tol`,
`primal`, `dual`, `h_dropped`, `h_err`, `w1_hexact`, `message` and `seconds`:
- `status`: `:ok`; `:runner_error` (no returned point, `w1 = NaN`);
  `:jacobian_error` (the Jacobian of f raised an exception at the point);
  `:merit_failure` (h or the subproblem failed at every tolerance of `MERIT_TOLS`);
- `w1`, `tol`, `primal`, `h_dropped`, `message`: from `merit_w1`;
- `dual`: `merit_w1_dual` for δ = 0 and at most 3 objectives, `NaN` otherwise;
- `h_err`: max_j |h_j(x) - δ‖A_j⁻ᵀx‖₁|, the error of `evalh!` against the closed
  form of h for the square `A_j` of the protocol (`NaN` for δ = 0, where
  `evalh!` sets h = 0). HiGHS's default tolerances give errors up to ~5e-9,
  the size of w₁ at the smallest threshold, √(2w₁) = 1e-4;
- `w1_hexact`: `merit_w1` with that closed form as h(x) (`NaN` for δ = 0, where
  it equals `w1`, and when Ipopt fails).
The file also holds `metadata` (source file, problems, `MERIT_TOLS`, Julia
version, date, git state of this repository and of `MOSolvers.jl`).
"""

using DrWatson
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO
using JLD2, Random, Dates, LinearAlgebra, MOSolvers, MultiObjectiveProblems

const MERIT_SOLVER = :x0  # `solver` of the rows of initial points

"""
    protocol(results_file)

Return `(problems, nrun, deltas, seed)` of the run that wrote `results_file`,
from its provenance records, which must all agree.
"""
function protocol(results_file::AbstractString)
    records = jldopen(file -> [file["$(AAS2025PDFreeMO.PROVENANCE_KEY)/$part"]
                               for part in keys(file[AAS2025PDFreeMO.PROVENANCE_KEY])], results_file)
    values = unique((Symbol.(r["partition"]["problems"]), r["nrun"], r["protocol_deltas"], r["seed"]) for r in records)
    length(values) == 1 || error("provenance records disagree on the protocol: $values")
    return only(values)
end

"""
    regenerate_inputs(problems, nrun, deltas, seed)

Return `Dict((problem, delta) => (A, initial_points))` drawn as
`run_all_problems.jl` draws them.
"""
function regenerate_inputs(problems, nrun, deltas, seed)
    Random.seed!(seed)
    inputs = Dict{Tuple{Symbol, Float64}, Tuple{Vector{Matrix{Float64}}, Vector{Vector{Float64}}}}()
    options = CommonSolverOptions()
    for problem in problems
        configs = generate_experiment_configs([problem], [:ProxGrad], nrun, deltas, options)
        for delta in deltas
            cs = sort(filter(c -> isequal(c.delta, delta), configs); by = c -> c.run_id)
            inputs[(problem, delta)] = (first(cs).data_matrices, [c.initial_point for c in cs])
        end
    end
    return inputs
end

"""
    merit_row(problem_instance, x, params, lb, ub, delta; solver, problem, run_id)

Row of the table for the point `x` (see the script docstring).
"""
function merit_row(problem_instance, x, params, A, lb, ub, delta; solver, problem, run_id)
    key = (solver = solver, problem = problem, delta = delta, run_id = run_id)
    empty = (w1 = NaN, sqrt_2w1 = NaN, tol = NaN, primal = NaN, dual = NaN, h_dropped = false, h_err = NaN,
             w1_hexact = NaN)
    seconds = @elapsed begin
        Jf = try
            MultiObjectiveProblems.eval_jacobian(problem_instance, x)
        catch e
            return (; key..., status = :jacobian_error, empty..., message = sprint(showerror, e), seconds = 0.0)
        end
        r = merit_w1(x, Jf, params)
        dual = delta == 0 && size(Jf, 1) <= 3 ? merit_w1_dual(x, Jf, lb, ub).w1 : NaN
        h_exact = [delta * norm(A[j]' \ x, 1) for j in eachindex(A)]
        w1_hexact = delta == 0 ? NaN : merit_w1(x, Jf, params; hx = h_exact).w1
    end
    h_err = delta == 0 ? NaN : maximum(abs.(r.hx - h_exact))
    r.success || return (; key..., status = :merit_failure, empty..., dual, h_err, w1_hexact, message = r.message, seconds)
    return (; key..., status = :ok, w1 = r.w1, sqrt_2w1 = sqrt(2 * max(r.w1, 0.0)), tol = r.tol,
            primal = r.primal, dual, h_dropped = r.h_dropped, h_err, w1_hexact, message = r.message, seconds)
end

"""
    merit_table(results_file, problems)

Rows of the returned points of `results_file` and of the initial points, for
`problems`.

# Throws
- `ErrorException`: If a stored initial point differs from the regenerated
  one, or a result that is not `:runner_error` lacks `final_point`.
"""
function merit_table(results_file::AbstractString, problems)
    protocol_problems, nrun, deltas, seed = protocol(results_file)
    inputs = regenerate_inputs(protocol_problems, nrun, deltas, seed)
    rows = NamedTuple[]
    jldopen(results_file, "r") do file
        solvers = filter(!=(AAS2025PDFreeMO.PROVENANCE_KEY), collect(keys(file)))
        for problem in problems
            problem_instance = getfield(MultiObjectiveProblems, problem)()
            lb, ub = MultiObjectiveProblems.recommended_bounds(problem_instance)
            started = time()
            for delta in deltas
                A, initial_points = inputs[(problem, delta)]
                params = merit_params(A, delta, lb, ub)
                for (run_id, x0) in enumerate(initial_points)
                    push!(rows, merit_row(problem_instance, x0, params, A, lb, ub, delta;
                                          solver = MERIT_SOLVER, problem, run_id))
                end
                for solver in solvers
                    group = "$solver/$problem/delta_$(AAS2025PDFreeMO.delta_tag(delta))"
                    haskey(file, group) || continue
                    for run in keys(file[group])
                        result = file["$group/$run"]
                        isequal(result.initial_point, initial_points[result.run_id]) ||
                            error("$group/$run: stored initial point differs from the regenerated one")
                        key = (solver = Symbol(solver), problem = problem, delta = delta, run_id = result.run_id)
                        if result.status == :runner_error
                            push!(rows, (; key..., status = :runner_error, w1 = NaN, sqrt_2w1 = NaN, tol = NaN,
                                         primal = NaN, dual = NaN, h_dropped = false, h_err = NaN, w1_hexact = NaN,
                                         message = result.message,
                                         seconds = 0.0))
                            continue
                        end
                        hasproperty(result, :final_point) && !isempty(result.final_point) ||
                            error("$group/$run has no final_point (file written before it existed?)")
                        push!(rows, merit_row(problem_instance, result.final_point, params, A, lb, ub, delta;
                                              solver = key.solver, problem, run_id = key.run_id))
                    end
                end
                MOSolvers.clear_evalh_cache!()  # its LP models are cached per `params`
            end
            println("[merit] problem=$problem rows=$(count(r -> r.problem == problem, rows)) seconds=$(round(time() - started; digits = 1))")
            flush(stdout)
        end
    end
    return [r for r in rows]
end

function metadata(results_file, problems)
    git(dir) = AAS2025PDFreeMO.git_state(dir)
    return Dict{String, Any}("results_file" => abspath(results_file), "problems" => string.(problems),
                             "merit_tols" => collect(MERIT_TOLS), "julia_version" => string(VERSION),
                             "date" => string(now()), "git" => git(projectdir()),
                             "git_mosolvers" => git(normpath(projectdir("..", "MOSolvers.jl"))))
end

function merit_main(args)
    if !isempty(args) && args[1] == "--join"
        length(args) >= 3 || error("usage: compute_merit.jl --join <output.jld2> <part.jld2> ...")
        output, parts = args[2], args[3:end]
        ispath(output) && error("$output already exists; choose another name")
        tables = [load(part) for part in parts]
        rows = reduce(vcat, [t["merit"] for t in tables])
        keys_ = [(r.solver, r.problem, r.delta, r.run_id) for r in rows]
        allunique(keys_) || error("a row appears in more than one part")
        jldsave(output; merit = rows, metadata = Dict{String, Any}("parts" => [t["metadata"] for t in tables]))
        println("[merit] $output: $(length(rows)) rows from $(length(parts)) parts")
        return
    end
    length(args) >= 2 || error("usage: compute_merit.jl <results.jld2> <output.jld2> [problem ...]")
    results_file, output = args[1], args[2]
    ispath(output) && error("$output already exists; choose another name")
    problems = length(args) > 2 ? Symbol.(args[3:end]) : first(protocol(results_file))
    rows = merit_table(results_file, problems)
    jldsave(output; merit = rows, metadata = metadata(results_file, problems))
    println("[merit] $output: $(length(rows)) rows")
end

if abspath(PROGRAM_FILE) == @__FILE__
    merit_main(ARGS)
end
