using Dates
using Random # Unique temporary filenames.

"""
    generate_experiment_configs(problems, solvers, nrun, deltas, common_options; solver_specific_options=Dict())

Generate experiment configurations with unique run identifiers per
(problem, solver, delta) combination.

# Arguments
- `problems`: Problems to test.
- `solvers`: Solvers to test.
- `nrun`: Number of runs per (problem, solver, delta) combination.
- `deltas`: Delta values to test.
- `common_options`: Shared options for all solvers.
- `solver_specific_options`: Optional solver-specific options.

# Returns
- `Vector{ExperimentConfig{T}}`: Experiment configurations.

# Note
Each configuration receives a `run_id` unique within each
(problem, solver, delta) combination, avoiding collisions in hierarchical
result storage.
"""
function generate_experiment_configs(problems, solvers, nrun, deltas, common_options::CommonSolverOptions{T}; solver_specific_options::Dict{Symbol, SolverSpecificOptions{T}} = Dict{Symbol, SolverSpecificOptions{T}}()) where T
    configs = ExperimentConfig{T}[]

    for problem_name in problems
        # Normalize problem name to a Symbol.
        problem_sym = isa(problem_name, Symbol) ? problem_name : Symbol(problem_name)

        problem_constructor = getfield(MultiObjectiveProblems, problem_sym)
        problem_instance = problem_constructor()

        # Generate initial points for this problem. Problems without registered
        # bounds use the package's recommended box (DEC-001 of the revision).
        n = problem_instance.nvar
        l, u = MultiObjectiveProblems.recommended_bounds(problem_instance)
        initial_points = [l + rand(n) .* (u - l) for _ in 1:nrun]

        # For each delta, precompute a single set of A matrices shared by all solvers.
        for delta in deltas
            data_matrices = datas(n, problem_instance.nobj)  # Fixed A for this (problem, delta).

            for solver in solvers
                # Normalize solver name to a Symbol.
                solver_sym = isa(solver, Symbol) ? solver : Symbol(string(solver))

                # Use solver-specific options when provided, or fall back to defaults.
                specific_opts = get(solver_specific_options, solver_sym, SolverSpecificOptions{T}())
                solver_config = SolverConfiguration(common_options, specific_opts)

                for (trial_idx, x0) in enumerate(initial_points)
                    config = ExperimentConfig(
                        solver_sym,
                        problem_sym,
                        trial_idx,  # Unique within each (problem, solver, delta).
                        delta,
                        copy(x0),
                        solver_config,
                        data_matrices
                    )
                    push!(configs, config)
                end
            end
        end
    end

    return configs
end

"""
    _save_results_to_jld2(filepath, results)

Persist a vector of experiment results to a JLD2 file. Internal helper used by
batch and final saving workflows.
"""
function _save_results_to_jld2(filepath::String, results::Vector{<:ExperimentResult})
    jldopen(filepath, "w") do file
        for result in results
            key = "$(result.solver_name)/$(result.problem_name)/delta_$(delta_tag(result.delta))/run_$(result.run_id)"
            file[key] = result
        end
    end
end

"""
    _copy_jld2_contents(source, dest, path="")

Recursively copy the contents of a JLD2 group into another group or file.

# Throws
- `error`: If an entry other than a group exists in both. Results and
  provenance records are never overwritten; entries copied before the conflict
  stay in `dest`.
"""
function _copy_jld2_contents(source::Union{JLD2.Group, JLD2.JLDFile}, dest::Union{JLD2.Group, JLD2.JLDFile}, path::String = "")
    for key in keys(source)
        entry = isempty(path) ? key : "$path/$key"
        if JLD2.haskey(dest, key)
            obj_source = source[key]
            obj_dest = dest[key]
            
            if obj_source isa JLD2.Group && obj_dest isa JLD2.Group
                _copy_jld2_contents(obj_source, obj_dest, entry)
            else
                error("JLD2 entry '$entry' exists in both files; refusing to overwrite it.")
            end
        else
            obj_source = source[key]
            if obj_source isa JLD2.Group
                new_group = JLD2.Group(dest, key)
                _copy_jld2_contents(obj_source, new_group, entry)
            else
                dest[key] = obj_source
            end
        end
    end
end

"""
    append_from_jld2(final_filepath, temp_filepath)

Append results from a temporary JLD2 file into a final file.

# Throws
- `error`: If a result or provenance record of `temp_filepath` is already in
  `final_filepath` (see `_copy_jld2_contents`).
"""
function append_from_jld2(final_filepath::String, temp_filepath::String)
    jldopen(final_filepath, "a+") do final_file
        jldopen(temp_filepath, "r") do temp_file
            _copy_jld2_contents(temp_file, final_file)
        end
    end
end

"""
    with_compile_time(f, compile_time::Ref{Float64})

Call `f()` and store in `compile_time[]` the seconds Julia spent compiling
during the call, also when `f` throws.

Compile timing is switched on around the call itself, so the value is never
`0.0` merely because timing was off. `Base.cumulative_compile_timing` keeps a
counter that callers such as `@time` raise and lower in pairs; timing is on
while it is nonzero. The counter is a `UInt8` that wraps, so after an unpaired
switch-off (0 → 255) a single switch-on would leave timing off: the counter is
therefore read back (`jl_measure_compile_time_enabled`, a Julia internal, checked
on Julia 1.12.1) and raised until it is nonzero, then lowered by as much at the
end, which restores the state found and never switches off a measurement made
elsewhere.
"""
function with_compile_time(f, compile_time::Ref{Float64})
    timing_counter = cglobal(:jl_measure_compile_time_enabled, UInt8)
    raised = 0
    while raised == 0 || unsafe_load(timing_counter) == 0
        Base.cumulative_compile_timing(true)
        raised += 1
    end
    start = Base.cumulative_compile_time_ns()[1]
    try
        return f()
    finally
        compile_time[] = (Base.cumulative_compile_time_ns()[1] - start) / 1e9
        for _ in 1:raised
            Base.cumulative_compile_timing(false)
        end
    end
end

"""
    run_single_experiment(config::ExperimentConfig{T}) where T

Run a single experiment and return the corresponding `ExperimentResult`, with
the compile time of the solver call (see `with_compile_time`).
"""
function run_single_experiment(config::ExperimentConfig{T}) where T
    problem_constructor = getfield(MultiObjectiveProblems, config.problem_name)
    problem_instance = problem_constructor()

    # Resolve solver options for the requested solver.
    options = get_solver_options(config.solver_name, config.solver_config)

    l, u = MultiObjectiveProblems.recommended_bounds(problem_instance)
    compile_time = Ref(0.0)

    try
        # Only the solver call is timed, the stretch whose time the solver reports.
        result = with_compile_time(compile_time) do
            if config.solver_name == :PDFPM || config.solver_name == :PDFPM_trace_scaled
                # Resolve the solver function and its options.
                solver_function = getfield(MOSolvers, :PDFPM)
                # Execute with precomputed matrices.
                solver_function(x -> MultiObjectiveProblems.eval_f(problem_instance, x),
                                config.data_matrices,
                                config.delta,
                                config.initial_point,
                                options; evalJf = x -> MultiObjectiveProblems.eval_jacobian(problem_instance, x),
                                lb = l, ub = u)
            elseif config.solver_name == :Dfree
                # Resolve the solver function and its options.
                solver_function = getfield(MOSolvers, :PDFPM)
                # Execute with precomputed matrices.
                solver_function(x -> MultiObjectiveProblems.eval_f(problem_instance, x),
                                config.data_matrices,
                                config.delta,
                                config.initial_point,
                                options;
                                lb = l, ub = u)    

            elseif config.solver_name == :ProxGrad || config.solver_name == :CondG
                # Resolve the solver function and its options.
                solver_function = getfield(MOSolvers, config.solver_name)
                # Execute with precomputed matrices.
                solver_function(x -> MultiObjectiveProblems.eval_f(problem_instance, x),
                                x -> MultiObjectiveProblems.eval_jacobian(problem_instance, x),
                                config.data_matrices,
                                config.delta,
                                config.initial_point,
                                options;
                                lb = l, ub = u)
            else
                error("Solver $(config.solver_name) not supported")
            end
        end
        if config.solver_name == :ProxGrad || config.solver_name == :CondG
            println("Solver message: ", result.message)
        end

        # Keep the metrics of nonconverged runs too: the analysis filters on
        # `converged`, and the status frequencies need every termination cause.
        return ExperimentResult(
            config.solver_name,
            solver_step_tolerance_rule(config.solver_name),
            config.problem_name,
            config.run_id,
            config.delta,
            config.initial_point,
            MOSolvers.converged(result),
            result.status,
            result.message,
            result.iter,
            result.n_f_evals,
            result.n_Jf_evals,
            result.total_time,
            compile_time[],
            copy(result.F_init),
            copy(result.Fval),
            deepcopy(result.x_trace),
            deepcopy(result.Fval_trace),
            copy(result.abs_theta_trace),
            copy(result.norm_progress_trace),
            copy(result.sigma_trace),
            copy(result.max_tr_B_trace)
        )
        
    catch e
        # Log the failure to aid debugging, then return a failed result.
        println("Error while running $(config.solver_name) on $(config.problem_name):")
        println(sprint(showerror, e, catch_backtrace()))
        return create_failed_result(config, problem_instance.nobj, sprint(showerror, e), compile_time[])
    end
end

"""
    run_experiment_with_batch_saving(configs; batch_size=50, filename_base="benchmark_live",
                                     outdir=datadir("sims"), provenance=collect_provenance(configs))

Run experiments and save results in batches to minimize data loss.

# Arguments
- `configs`: Experiment configurations.
- `batch_size`: Number of results persisted per batch.
- `filename_base`: Base name for the live results file.
- `outdir`: Directory of the live results file and of the temporary batch files.
- `provenance`: Record stored under `PROVENANCE_KEY/<problem>` for every problem
  in `configs` (see `collect_provenance`).

# Returns
- `Vector{ExperimentResult{T}}`: All collected results.

# Throws
- `error`: If the live results file already holds provenance for one of the
  problems (see `write_provenance`).
"""
function run_experiment_with_batch_saving(
    configs::Vector{ExperimentConfig{T}};
    batch_size::Int = 50,
    filename_base::String = "benchmark_live",
    outdir::String = datadir("sims"),
    provenance::Dict{String, Any} = collect_provenance(configs)
) where T
    all_results = ExperimentResult{T}[]
    problems = unique(config.problem_name for config in configs)
    final_filepath = joinpath(outdir, "$(filename_base).jld2")
    mkpath(outdir)
    
    if length(configs) <= batch_size
        println("Total experiments ($(length(configs))) do not exceed batch size ($batch_size). Batch saving is disabled.")
        for config in configs
            result = run_single_experiment(config)
            push!(all_results, result)
        end
        _save_results_to_jld2(final_filepath, all_results)
        write_provenance(final_filepath, provenance, problems)
        return all_results
    end

    current_batch = ExperimentResult{T}[]
    
    println("Batch saving enabled. Intermediate results will be saved to: $final_filepath")
    write_provenance(final_filepath, provenance, problems)

    for (i, config) in enumerate(configs)
        result = run_single_experiment(config)
        push!(all_results, result)
        push!(current_batch, result)

        if length(current_batch) >= batch_size || i == length(configs)
            println("\nProcessing batch. Saving $(length(current_batch)) results...")
            
            # RandomDevice keeps the global stream untouched: drawing from it here
            # would make the next problem's initial points and A matrices depend
            # on the number of batches, hence on the solver list.
            temp_filename = "temp_batch_$(randstring(RandomDevice(), 8)).jld2"
            temp_filepath = joinpath(outdir, temp_filename)
            
            try
                _save_results_to_jld2(temp_filepath, current_batch)
                println("Temporary batch saved to: $temp_filepath")

                append_from_jld2(final_filepath, temp_filepath)
                println("Batch appended to: $final_filepath")
            finally
                if isfile(temp_filepath)
                    rm(temp_filepath)
                    println("Temporary file removed.")
                end
            end
            
            empty!(current_batch)
        end
    end

    println("\nBatch experiment run complete.")
    return all_results
end

"""
    create_failed_result(config, nobj, message, compile_time=0.0)

Build an `ExperimentResult` for a run that raised an exception, with status
`:runner_error`, the exception text as `message` and the compile time measured
until the exception.
"""
function create_failed_result(config::ExperimentConfig{T}, nobj::Int, message::AbstractString,
                              compile_time::Float64 = 0.0) where T
    return ExperimentResult{T}(
        config.solver_name,
        solver_step_tolerance_rule(config.solver_name),
        config.problem_name,
        config.run_id,
        config.delta,
        config.initial_point,
        false,
        :runner_error,
        String(message),
        0,
        0,
        0,
        0.0,
        compile_time,
        fill(T(NaN), nobj),
        fill(T(NaN), nobj),
        Vector{T}[],
        Vector{T}[],
        T[],
        T[],
        T[],
        T[]
    )
end

"""
    run_experiment(configs::Vector{ExperimentConfig{T}}) where T

Run all experiments in `configs` and return the collected results.
"""
function run_experiment(configs::Vector{ExperimentConfig{T}}) where T
    all_results = ExperimentResult{T}[]
    
    println("Running $(length(configs)) experiments")
    
    for config in configs
        result = run_single_experiment(config)
        # Add to the aggregated results.
        push!(all_results, result)
    end
    
    return all_results
end
