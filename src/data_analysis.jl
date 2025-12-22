"""
Data analysis utilities for multiobjective optimization experiments.

Provides helper functions to load, filter, and inspect results stored in JLD2
files.
"""

using DrWatson
using JLD2
using MOProblems

# ========================================================================================
# DATA DISCOVERY HELPERS
# ========================================================================================

"""
    list_jld2_files()

List all JLD2 files available in the simulation directory managed by DrWatson.

# Returns
- `Vector{String}`: File names (not paths) found under `data/sims/`.

# Note
Files are expected to live in `data/sims/`, the default DrWatson data folder.
"""
function list_jld2_files()
    sims_dir = datadir("sims")
    
    if !isdir(sims_dir)
        println("Simulation directory not found: $sims_dir")
        return String[]
    end
    
    files = readdir(sims_dir)
    jld2_files = filter(file -> endswith(file, ".jld2"), files)
    
    if isempty(jld2_files)
        println("No JLD2 files found in: $sims_dir")
        return String[]
    end
    
    println("Found JLD2 files:")
    for (i, file) in enumerate(jld2_files)
        println("$i. $file")
    end
    
    return jld2_files
end

"""
    list_solvers_for_problem(filepath::String, problem_name::Symbol)

List every solver that contains data for a specific problem in a JLD2 file.

# Arguments
- `filepath::String`: Absolute path to the JLD2 file.
- `problem_name::Symbol`: Name of the problem to inspect.

# Returns
- `Vector{String}`: Solver names that include the requested problem.

# Note
The expected hierarchy inside the JLD2 file is `solver/problem/run_id`.
"""
function list_solvers_for_problem(filepath::String, problem_name::Symbol)
    solvers = String[]
    jldopen(filepath, "r") do file
        for solver_name in keys(file)
            if haskey(file[solver_name], string(problem_name))
                push!(solvers, solver_name)
            end
        end
    end
    return solvers
end

"""
    is_biobjective_problem(problem_name::Symbol)

Check whether a problem defines exactly two objectives.

# Arguments
- `problem_name::Symbol`: Problem name to inspect.

# Returns
- `Bool`: `true` when the problem is biobjective, `false` otherwise.

# Note
Returns `false` when the problem constructor is not present in `MOProblems`.
Other instantiation errors are logged and rethrown to surface unexpected issues.
"""
function is_biobjective_problem(problem_name::Symbol)
    problem_constructor = try
        getfield(MOProblems, problem_name)
    catch e
        if e isa UndefVarError && e.var == problem_name
            @warn "Problem not found in MOProblems; treating as non-biobjective." problem_name
            return false
        end
        rethrow(e)
    end

    try
        problem_instance = problem_constructor()
        return problem_instance.nobj == 2
    catch e
        @error "Failed to instantiate problem for biobjective check" problem_name exception = (e, catch_backtrace())
        rethrow(e)
    end
end

"""
    list_biobjective_problems(filepath::String)

List all biobjective problems present in a JLD2 file.

# Arguments
- `filepath::String`: Absolute path to the JLD2 file.

# Returns
- `Vector{Symbol}`: Biobjective problems discovered in the file.

# Note
Traverses the JLD2 structure to determine whether each problem is biobjective.
The expected hierarchy is `solver/problem/run_id`.
"""
function list_biobjective_problems(filepath::String)
    println("\nScanning for biobjective problems in: $(basename(filepath))")
    
    biobjective_problems = Symbol[]
    
    jldopen(filepath, "r") do file
        available_solvers = collect(keys(file))
        
        for solver in available_solvers
            solver_group = file[solver]
            for problem_name in keys(solver_group)
                problem_sym = Symbol(problem_name)
                
                # Avoid duplicates when multiple solvers include the same problem
                if !(problem_sym in biobjective_problems)
                    if is_biobjective_problem(problem_sym)
                        push!(biobjective_problems, problem_sym)
                    end
                end
            end
        end
    end
    
    if isempty(biobjective_problems)
        println("No biobjective problems found in the file.")
    else
        println("Biobjective problems found: $biobjective_problems")
    end
    
    return biobjective_problems
end

"""
    filter_solvers(available_solvers::Vector{String}, target_solvers::Vector{String})

Filter the available solvers to keep only the requested names.

# Arguments
- `available_solvers::Vector{String}`: Solvers found in the JLD2 file.
- `target_solvers::Vector{String}`: Solvers requested for analysis.

# Returns
- `Vector{String}`: Solvers that will be analyzed.

# Note
Use this helper to restrict analysis to specific solvers even when the JLD2 file
contains additional data.
"""
function filter_solvers(available_solvers::Vector{String}, target_solvers::Vector{String})
    solvers_to_analyze = filter(solver -> solver in target_solvers, available_solvers)
    
    if isempty(solvers_to_analyze)
        println("None of the requested solvers were found in the file.")
        println("Available solvers: $available_solvers")
        println("Requested solvers: $target_solvers")
    else
        println("Solvers selected for analysis: $solvers_to_analyze")
    end
    
    return solvers_to_analyze
end

# ========================================================================================
# DATA EXTRACTION HELPERS
# ========================================================================================

"""
    extract_performance_data(filepath::String, metric::String, target_solvers::Vector{String})

Build a performance matrix from a JLD2 file for the requested metric and solvers.

# Arguments
- `filepath::String`: Absolute path to the JLD2 file.
- `metric::String`: Metric name to extract (e.g. `"iter"`, `"total_time"`).
- `target_solvers::Vector{String}`: Solvers to include as columns in the matrix.

# Returns
- `Matrix{Float64}`: Performance matrix (instances × solvers) with `NaN`
  indicating failed runs or missing values.
- `Vector{Tuple{String, Float64, Int}}`: Row metadata as `(problem, delta, run_id)`.

# Notes
- The expected hierarchy is `solver/problem/delta/run_id`.
- Only runs flagged as `success` and containing the requested metric are recorded.
"""
function extract_performance_data(filepath::String, metric::String, target_solvers::Vector{String})
    println("\nExtracting performance data from: $(basename(filepath))")
    println("Metric: $metric")

    jldopen(filepath, "r") do file
        available_solvers = collect(keys(file))
        solvers_to_analyze = filter_solvers(available_solvers, target_solvers)
        
        if isempty(solvers_to_analyze)
            println("None of the requested solvers were found in the file.")
            return Matrix{Float64}(undef, 0, 0), []
        end

        # Collect every unique instance (problem, delta, run_id)
        instance_info = Set{Tuple{String, Float64, Int}}()
        for solver in solvers_to_analyze
            # if !haskey(file, solver); continue; end
            solver_group = file[solver]
            for problem in keys(solver_group)
                problem_group = solver_group[problem]
                for delta_key in keys(problem_group)
                    # if !startswith(delta_key, "delta_"); continue; end
                    delta_str = replace(delta_key, "delta_" => "")
                    delta_val = parse(Float64, replace(delta_str, "-" => "."))
                    
                    delta_group = problem_group[delta_key]
                    for run_key in keys(delta_group)
                        # if !startswith(run_key, "run_"); continue; end
                        run_id = parse(Int, replace(run_key, "run_" => ""))
                        push!(instance_info, (problem, delta_val, run_id))
                    end
                end
            end
        end

        sorted_instance_info = sort(collect(instance_info), by = x -> (x[1], x[2], x[3]))
        
        if isempty(sorted_instance_info)
            println("No result instances found in the file.")
            return Matrix{Float64}(undef, 0, 0), []
        end

        println("Total instances found: $(length(sorted_instance_info))")

        # Build performance matrix (instances × solvers)
        perf_matrix = fill(NaN, length(sorted_instance_info), length(solvers_to_analyze))
        
        # Populate the matrix
        for (instance_idx, (problem, delta, run_id)) in enumerate(sorted_instance_info)
            for (solver_idx, solver) in enumerate(solvers_to_analyze)
                delta_str = replace(string(delta), "." => "-")
                delta_key = "delta_$(delta_str)"
                run_key = "run_$(run_id)"
                
                path_exists = haskey(file, solver) &&
                              haskey(file[solver], problem) &&
                              haskey(file[solver][problem], delta_key) &&
                              haskey(file[solver][problem][delta_key], run_key)

                if path_exists
                    result = file[solver][problem][delta_key][run_key]
                    
                    if result.success && hasproperty(result, Symbol(metric))
                        perf_matrix[instance_idx, solver_idx] = getproperty(result, Symbol(metric))
                    end
                end
            end
        end
        
        return perf_matrix, sorted_instance_info
    end
end

"""
    extract_problem_data(filepath::String, problem_name::Symbol, solver_name::String)

Extract the final objective values for a specific problem and solver, grouped by
delta.

# Arguments
- `filepath::String`: Absolute path to the JLD2 file.
- `problem_name::Symbol`: Problem name to extract.
- `solver_name::String`: Solver name to extract.

# Returns
- `Tuple{Vector{Float64}, Dict{Float64, Vector{Vector{Float64}}}}`:
  - Sorted list of delta values present in the file.
  - Dictionary keyed by delta, with each entry containing the final objective
    points for successful runs.

# Note
Designed for biobjective problems where each final point is a vector `[f1, f2]`.
Data are organized by `delta` to simplify comparisons. The expected hierarchy is
`solver/problem/delta/run_id`.
"""
function extract_problem_data(filepath::String, problem_name::Symbol, solver_name::String)
    println("\nExtracting data for problem: $problem_name, solver: $solver_name")
    
    # Storage for values organized by delta
    deltas = Set{Float64}()
    final_points_dict = Dict{Float64, Vector{Vector{Float64}}}()
    
    jldopen(filepath, "r") do file
        # Verify the solver exists in the file
        if !haskey(file, solver_name)
            println("Warning: solver '$solver_name' not found in the file.")
            return Float64[], Dict{Float64, Vector{Vector{Float64}}}()
        end
        
        solver_group = file[solver_name]
        
        # Verify the problem exists for this solver
        if haskey(solver_group, string(problem_name))
            problem_group = solver_group[string(problem_name)]
            
            # Navigate structure: solver/problem/delta/run_id
            for delta_key in keys(problem_group)
                if startswith(delta_key, "delta_")
                    # Extract delta value
                    delta_str = replace(delta_key, "delta_" => "")
                    delta_val = parse(Float64, replace(delta_str, "-" => "."))
                    
                    # Collect run_ids for this delta
                    delta_group = problem_group[delta_key]
                    for run_key in keys(delta_group)
                        if startswith(run_key, "run_")
                            result = delta_group[run_key]
                            
                            # Record only successful runs
                            if result.success
                                final_point = result.final_objective_value
                                
                                # Track the delta value
                                push!(deltas, delta_val)
                                
                                # Initialize storage for this delta if needed
                                if !haskey(final_points_dict, delta_val)
                                    final_points_dict[delta_val] = Vector{Vector{Float64}}()
                                end
                                
                                # Append final point
                                push!(final_points_dict[delta_val], final_point)
                            end
                        end
                    end
                end
            end
        else
            println("Warning: problem '$problem_name' not found for solver '$solver_name'.")
        end
    end
    
    # Sort collected delta values
    deltas_vector = sort(collect(deltas))
    
    println("Deltas found: $deltas_vector")
    if !isempty(deltas_vector)
        for delta in deltas_vector
            println("  Delta $delta: $(length(final_points_dict[delta])) points")
        end
    end
    
    return deltas_vector, final_points_dict
end
