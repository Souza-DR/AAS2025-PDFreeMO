"""
    ExperimentResult

Container for the inputs and results of a single solver run on an optimization
problem.

# Fields
- `solver_name::Symbol`: Solver identifier.
- `problem_name::Symbol`: Problem identifier.
- `run_id::Int`: Run identifier (e.g., 1 to 200 for each starting point).
- `delta::T`: Robustness parameter value.
- `initial_point::Vector{T}`: Starting point used by the solver.
- `success::Bool`: Whether the solver completed successfully.
- `iter::Int`: Total number of solver iterations.
- `n_f_evals::Int`: Total number of objective function evaluations.
- `n_Jf_evals::Int`: Total number of Jacobian evaluations.
- `total_time::Float64`: Elapsed runtime in seconds.
- `F_init::Vector{T}`: Initial objective vector value.
- `final_objective_value::Vector{T}`: Final objective vector value.

"""
struct ExperimentResult{T<:Real}
    # Input parameters
    solver_name::Symbol
    problem_name::Symbol
    run_id::Int
    delta::T
    initial_point::Vector{T}

    # Output metrics
    success::Bool
    iter::Int
    n_f_evals::Int
    n_Jf_evals::Int
    total_time::Float64
    F_init::Vector{T}
    final_objective_value::Vector{T}
end

"""
    ExperimentConfig{T}

Container for all parameters required to run a single experiment instance in a
reproducible way. The struct enforces consistent types and normalizes names.

# Fields
- `solver_name::Symbol`: Solver identifier.
- `problem_name::Symbol`: Problem identifier.
- `run_id::Int`: Run identifier (e.g., 1 to 100).
- `delta::T`: Robustness parameter value.
- `initial_point::Vector{T}`: Starting point for the optimization.
- `solver_config::SolverConfiguration{T}`: Solver configuration (common and specific settings).
- `data_matrices::Vector{Matrix{T}}`: Precomputed `A` matrices fixed for the pair
  (problem, delta), used by the nondifferentiable term `H`.
"""
struct ExperimentConfig{T<:Real}
    solver_name::Symbol
    problem_name::Symbol
    run_id::Int
    delta::T
    initial_point::Vector{T}
    solver_config::SolverConfiguration{T}
    # Fixed A matrices for (problem, delta)
    data_matrices::Vector{Matrix{T}}
    
    # Inner constructor with normalization/conversion
    function ExperimentConfig{T}(
        solver_name, problem_name, run_id, delta, 
        initial_point, solver_config, data_matrices
    ) where T<:Real
        
        # Normalize names to Symbol.
        problem_sym = problem_name isa Symbol ? problem_name : Symbol(string(problem_name))
        solver_sym = solver_name isa Symbol ? solver_name : Symbol(string(solver_name))
        
        # Convert to the expected concrete types.
        delta_val = T(delta)
        run_id_val = Int(run_id)
        initial_point_val = Vector{T}(initial_point)
        data_matrices_val = Vector{Matrix{T}}(data_matrices)

        if isempty(initial_point_val)
            error("initial_point must be non-empty.")
        end
        if !isempty(data_matrices_val)
            ref_size = size(data_matrices_val[1])
            for (i, mat) in enumerate(data_matrices_val)
                if size(mat) != ref_size
                    error("data_matrices must all have the same size; mismatch at index $(i).")
                end
            end
        end
        
        new{T}(solver_sym, problem_sym, run_id_val, delta_val, 
                initial_point_val, solver_config, data_matrices_val)
    end
end

# Convenience outer constructor.
function ExperimentConfig(
    solver_name, problem_name, run_id, delta, 
    initial_point, solver_config, data_matrices
)
    T = eltype(initial_point)
    return ExperimentConfig{T}(
        solver_name, problem_name, run_id, delta, 
        initial_point, solver_config, data_matrices
    )
end