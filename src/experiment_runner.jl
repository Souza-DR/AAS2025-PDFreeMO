using Dates
using Random # Added to generate unique temporary filenames.

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

        problem_constructor = getfield(MOProblems, problem_sym)
        problem_instance = problem_constructor()

        # Generate initial points for this problem.
        n = problem_instance.nvar
        l, u = problem_instance.bounds
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
            delta_str = replace(string(result.delta), "." => "-")
            key = "$(result.solver_name)/$(result.problem_name)/delta_$(delta_str)/run_$(result.run_id)"
            file[key] = result
        end
    end
end

"""
    _copy_jld2_contents(source, dest)

Recursively copy the contents of a JLD2 group into another group or file.
"""
function _copy_jld2_contents(source::Union{JLD2.Group, JLD2.JLDFile}, dest::Union{JLD2.Group, JLD2.JLDFile})
    for key in keys(source)
        if JLD2.haskey(dest, key)
            obj_source = source[key]
            obj_dest = dest[key]
            
            if obj_source isa JLD2.Group && obj_dest isa JLD2.Group
                _copy_jld2_contents(obj_source, obj_dest)
            else
                println("Warning: key '$key' caused a conflict. Overwriting destination.")
                dest[key] = obj_source
            end
        else
            obj_source = source[key]
            if obj_source isa JLD2.Group
                new_group = JLD2.Group(dest, key)
                _copy_jld2_contents(obj_source, new_group)
            else
                dest[key] = obj_source
            end
        end
    end
end

"""
    append_from_jld2(final_filepath, temp_filepath)

Append results from a temporary JLD2 file into a final file.
"""
function append_from_jld2(final_filepath::String, temp_filepath::String)
    jldopen(final_filepath, "a+") do final_file
        jldopen(temp_filepath, "r") do temp_file
            _copy_jld2_contents(temp_file, final_file)
        end
    end
end

"""
    run_single_experiment(config::ExperimentConfig{T}) where T

Run a single experiment and return the corresponding `ExperimentResult`.
"""
function run_single_experiment(config::ExperimentConfig{T}) where T
    problem_constructor = getfield(MOProblems, config.problem_name)
    problem_instance = problem_constructor()

    # Resolve solver options for the requested solver.
    options = get_solver_options(config.solver_name, config.solver_config)
       
    l, u = problem_instance.bounds
        
    try        
        if config.solver_name == :PDFPM
            # Resolve the solver function and its options.
            solver_function = getfield(MOSolvers, :PDFPM)
            if config.problem_name == :AAS1 || config.problem_name == :AAS2
                # Execute with precomputed matrices.
                result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                        config.data_matrices,
                                        config.delta,
                                        config.initial_point,
                                        options;
                                        lb = l, ub = u)
            else
                # Execute with precomputed matrices.
                result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                        config.data_matrices,
                                        config.delta,
                                        config.initial_point,
                                        options; evalJf = x -> safe_evalJf_solver(problem_instance, x),
                                        lb = l, ub = u)
            end
        elseif config.solver_name == :Dfree
            # Resolve the solver function and its options.
            solver_function = getfield(MOSolvers, :PDFPM)
            # Execute with precomputed matrices.
            result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                     config.data_matrices,
                                     config.delta,
                                     config.initial_point,
                                     options;
                                     lb = l, ub = u)    
        
        elseif config.solver_name == :ProxGrad || config.solver_name == :CondG
            # Resolve the solver function and its options.
            solver_function = getfield(MOSolvers, config.solver_name)
            # Execute with precomputed matrices.
            result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                     x -> safe_evalJf_solver(problem_instance, x),
                                     config.data_matrices,
                                     config.delta,
                                     config.initial_point,
                                     options;
                                     lb = l, ub = u)
            println("Solver message: ", result.message)
        else
            error("Solver $(config.solver_name) not supported")
        end

        # Return a result even when the solver reports failure.
        if result.success
            res = ExperimentResult(
                config.solver_name,
                config.problem_name,
                config.run_id,
                config.delta,
                config.initial_point,
                true,
                result.iter,
                result.n_f_evals,
                result.n_Jf_evals,
                result.total_time,
                copy(result.F_init),
                copy(result.Fval)
            )
            return res
        else
            # Solver finished but reported failure.
            return create_failed_result(config, problem_instance.nobj)
        end
        
    catch e
        # Log the failure to aid debugging, then return a failed result.
        println("Error while running $(config.solver_name) on $(config.problem_name):")
        println(sprint(showerror, e, catch_backtrace()))
        return create_failed_result(config, problem_instance.nobj)
    end
end

"""
    run_experiment_with_batch_saving(configs; batch_size=50, filename_base="benchmark_live")

Run experiments and save results in batches to minimize data loss.

# Arguments
- `configs`: Experiment configurations.
- `batch_size`: Number of results persisted per batch.
- `filename_base`: Base name for the live results file.

# Returns
- `Vector{ExperimentResult{T}}`: All collected results.
"""
function run_experiment_with_batch_saving(
    configs::Vector{ExperimentConfig{T}};
    batch_size::Int = 50,
    filename_base::String = "benchmark_live"
) where T
    all_results = ExperimentResult{T}[]
    
    if length(configs) <= batch_size
        println("Total experiments ($(length(configs))) do not exceed batch size ($batch_size). Batch saving is disabled.")
        for config in configs
            result = run_single_experiment(config)
            push!(all_results, result)
        end
        _save_results_to_jld2(datadir("sims", "$(filename_base).jld2"), all_results)
        return all_results
    end

    current_batch = ExperimentResult{T}[]
    final_filepath = datadir("sims", "$(filename_base).jld2")
    
    println("Batch saving enabled. Intermediate results will be saved to: $final_filepath")
    mkpath(datadir("sims"))

    for (i, config) in enumerate(configs)
        result = run_single_experiment(config)
        push!(all_results, result)
        push!(current_batch, result)

        if length(current_batch) >= batch_size || i == length(configs)
            println("\nProcessing batch. Saving $(length(current_batch)) results...")
            
            temp_filename = "temp_batch_$(randstring(8)).jld2"
            temp_filepath = joinpath(datadir("sims"), temp_filename)
            
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
    create_failed_result(config, nobj)

Build an `ExperimentResult` for a failed run.
"""
function create_failed_result(config::ExperimentConfig{T}, nobj::Int) where T
    return ExperimentResult{T}(
        config.solver_name,
        config.problem_name,
        config.run_id,
        config.delta,
        config.initial_point,
        false,
        0,
        0,
        0,
        0.0,
        fill(T(NaN), nobj),
        fill(T(NaN), nobj)
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