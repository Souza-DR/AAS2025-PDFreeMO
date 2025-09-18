using Plots

"""
    datas(n, m, delta)

Gera um vetor de `m` matrizes `n x n` para serem usadas nos experimentos.

Se `delta` for zero, as matrizes geradas são matrizes de zeros. Caso contrário,
são matrizes com elementos aleatórios uniformemente distribuídos entre 0 e 1.

# Arguments
- `n::Int`: Dimensão das matrizes (número de variáveis do problema).
- `m::Int`: Número de matrizes a serem geradas (número de objetivos do problema).
- `delta::Real`: Parâmetro de robustez. Se `delta == 0`, gera matrizes nulas.

# Returns
- `Vector{Matrix{Float64}}`: Um vetor contendo `m` matrizes `n x n`.
"""
function datas(n, m, delta)
    A = Vector{Matrix{Float64}}(undef, m)
    # for ind = 1:m
    #     if delta == 0.0
    #         A[ind] = zeros(n, n)
    #     else
    #         A[ind] = rand(n, n)
    #     end
    # end
    
    for ind = 1:m
        A[ind] = rand(n, n)
    end

    return A
end

# Funções seguras de avaliação que capturam erros de domínio
function safe_evalf(problem, x)
    try
        result = MOProblems.eval_f(problem, x)
        return (success = true, value = result, error = nothing)
    catch e
        if isa(e, MOProblems.DomainViolationError)
            # Violação de domínio - falha esperada
            return (success = false, value = nothing, error = e)
        else
            # Outro tipo de erro - pode ser um bug real
            rethrow(e)
        end
    end
end

function safe_evalJf(problem, x)
    try
        result = MOProblems.eval_jacobian(problem, x)
        return (success = true, value = result, error = nothing)
    catch e
        if isa(e, MOProblems.DomainViolationError)
            # Violação de domínio - falha esperada
            return (success = false, value = nothing, error = e)
        else
            # Outro tipo de erro - pode ser um bug real
            rethrow(e)
        end
    end
end

# Funções compatíveis com a interface do solver
function safe_evalf_solver(problem, x)
    try
        return MOProblems.eval_f(problem, x)
    catch e
        if isa(e, MOProblems.DomainViolationError)
            # Violação de domínio - lançar erro para o solver tratar
            throw(e)
        else
            # Outro tipo de erro - pode ser um bug real
            rethrow(e)
        end
    end
end

function safe_evalJf_solver(problem, x)
    try
        return MOProblems.eval_jacobian(problem, x)
    catch e
        if isa(e, MOProblems.DomainViolationError)
            # Violação de domínio - lançar erro para o solver tratar
            throw(e)
        else
            # Outro tipo de erro - pode ser um bug real
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
            result = safe_evalf(problem, x)
            if result.success
                push!(f1_vals, result.value[1])
                push!(f2_vals, result.value[2])
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
                
                result = safe_evalf(problem, x)
                if result.success
                    if 1.0 == 1.0
                    # if result.value[1] <= 0.5 && result.value[2] <= 1.0
                        push!(f1_vals, result.value[1])
                        push!(f2_vals, result.value[2])
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