using MOProblems

"""
    datas(n, m)

Generate a vector of `m` random `n×n` matrices (one per objective).

# Arguments
- `n::Int`: Matrix dimension (number of variables).
- `m::Int`: Number of matrices to generate (number of objectives).

# Returns
- `Vector{Matrix{Float64}}`: `m` random `n×n` matrices.
"""
function datas(n, m)
    A = Vector{Matrix{Float64}}(undef, m)
    for ind = 1:m
        A[ind] = rand(n, n)
    end

    return A
end

# Safe wrappers compatible with the solver interface

"""
    safe_evalf_solver(problem, x)

Evaluate the objective vector `f(x)` catching domain violations so the solver
can handle them, while rethrowing unexpected errors.
"""
function safe_evalf_solver(problem, x)
    try
        return MOProblems.eval_f(problem, x)
    catch e
        if isa(e, MOProblems.DomainViolationError)
            # Domain violation – let the solver handle it
            throw(e)
        else
            # Unexpected error – propagate for visibility
            rethrow(e)
        end
    end
end

"""
    safe_evalJf_solver(problem, x)

Evaluate the Jacobian `Jf(x)` catching domain violations so the solver can
handle them, while rethrowing unexpected errors.
"""
function safe_evalJf_solver(problem, x)
    try
        return MOProblems.eval_jacobian(problem, x)
    catch e
        if isa(e, MOProblems.DomainViolationError)
            # Domain violation – let the solver handle it
            throw(e)
        else
            # Unexpected error – propagate for visibility
            rethrow(e)
        end
    end
end

"""
    extract_objective_space_data(problem; grid_points=100)

Extracts objective space data points from a biobjective problem without creating a plot.

# Arguments
- `problem`: MOProblems.jl problem (must have exactly 2 objectives)
- `grid_points::Int=100`: Number of grid points for each dimension

# Returns
- `Tuple{Vector{Float64}, Vector{Float64}}`: Arrays of f₁ and f₂ values
"""
function extract_objective_space_data(problem; grid_points=100)
    # Check if the problem has exactly 2 objectives
    if problem.nobj != 2
        error("This function supports only problems with 2 objectives. Problem $(problem.name) has $(problem.nobj) objectives.")
    end

    println("Extracting objective space data for $(problem.name)...")

    f1_vals = Float64[]
    f2_vals = Float64[]
    
    n = problem.nvar
    lb = problem.bounds[1]  # lower bound
    ub = problem.bounds[2]  # upper bound
    
    if n == 1
        # For problems with 1 variable, create only a line
        x_range = range(lb[1], ub[1], length=grid_points)
        for x1 in x_range
            x = [x1]
            try
                val = safe_evalf_solver(problem, x)
                push!(f1_vals, val[1])
                push!(f2_vals, val[2])
            catch e
                if !isa(e, MOProblems.DomainViolationError)
                    rethrow(e)
                end
            end
        end
    else
        # For problems with 2+ variables, create a 2D grid
        # Use the first two variables to create the grid
        x_range = range(lb[1], ub[1], length=grid_points)
        y_range = range(lb[2], ub[2], length=grid_points)
        
        for x1 in x_range
            for x2 in y_range
                # Create vector with first 2 variables and mean values for the others
                x = zeros(n)
                x[1] = x1
                x[2] = x2
                
                # For remaining variables, use the midpoint of the interval
                for i in 3:n
                    x[i] = (lb[i] + ub[i]) / 2
                end
                
                try
                    val = safe_evalf_solver(problem, x)
                    push!(f1_vals, val[1])
                    push!(f2_vals, val[2])
                catch e
                    if !isa(e, MOProblems.DomainViolationError)
                        rethrow(e)
                    end
                end
            end
        end
    end

    # Check if we have valid points
    if isempty(f1_vals)
        error("No valid points found for problem $(problem.name). Check the domain limits.")
    end

    println("Extracted $(length(f1_vals)) objective space points.")
    return f1_vals, f2_vals
end

function _ensure_cairomakie_available()
    try
        @eval using CairoMakie
    catch e
        error(
            "quality = \"high\" requer CairoMakie no ambiente.\n" *
            "Instale com:\n" *
            "  julia --project -e 'using Pkg; Pkg.add(\"CairoMakie\")'\n\n" *
            "Erro original: $(e)",
        )
    end
    return nothing
end