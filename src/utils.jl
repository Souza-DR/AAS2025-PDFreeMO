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
    plot_objective_space(problem; grid_points=100)

Generates a plot of the objective space image for biobjective problems (2 objectives).
The function evaluates the vector function on a grid of points from the decision space
and plots the resulting objective values.

# Arguments
- `problem`: MOProblems.jl problem (must have exactly 2 objectives)
- `grid_points::Int=100`: Number of grid points for each dimension

# Returns
- `Plots.Plot`: Created plot object

# Note
This function is specific for biobjective problems (2 objectives).
"""
function plot_objective_space(problem; grid_points=100)
    # Extract the data points using the dedicated function
    f1_vals, f2_vals = extract_objective_space_data(problem; grid_points=grid_points)
    
    # Create the plot
    p = scatter(f1_vals, f2_vals,
                ms=1, 
                markerstrokewidth=0, 
                alpha=0.3, 
                color=:cornflowerblue,
                label="Objective Space Image",
                xlabel="F₁(x)",
                ylabel="F₂(x)",
                title="Objective Space Image for $(problem.name)",
                grid=true,
                legend=false)

    return p
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
                    push!(f1_vals, result.value[1])
                    push!(f2_vals, result.value[2])
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

# WARNING: This function dont work for now
function plot_trajectories(problem, solver, delta, x0)

    # Criar diretórios se não existirem
    for delta in DELTAS
        delta_str = replace(string(delta), "." => "-")
        mkpath("plots/$delta_str")
    end
    mkpath("plots/deltas")

    # WARNING: This image get f + h, not only f
    println("Gerando a imagem das trajetórias para $(problem.name)...")

    p = plot(title="Trajetórias de Otimização - Problema $(problem.name) ($(solver))",
             xlabel="F₁(x)",
             ylabel="F₂(x)",
             legend=:topright,
             grid=true)

    # Plotar trajetória
    scatter!(p, [F0[1]], [F0[2]], ms=3, color=:gray, alpha=0.6, label=false)
    scatter!(p, [result.Fval[1]], [result.Fval[2]], ms=3, color=:red, alpha=0.8, label=false)
    plot!(p, [F0[1], result.Fval[1]], [F0[2], result.Fval[2]], 
        color=:black, alpha=0.4, linewidth=1, label=false)

    # Combinar e salvar plots
    if objective_space_plot !== nothing && trajectories_plot !== nothing
        combined_plot = plot(objective_space_plot, trajectories_plot, 
                           layout = (1, 2), 
                           size = (1200, 600))
        
        delta_str = replace(string(delta), "." => "-")
        filename = "plots/$delta_str/pareto_$(problem_name)_DFreeMO_delta_$delta_str.png"
        savefig(combined_plot, filename)
        println("Gráfico salvo como '$filename'")
    end

    # Criar plot comparativo de deltas
    if !isempty(final_points_dict)
        delta_comparison_plot = create_delta_comparison_plot(problem_instance, DELTAS, final_points_dict)
        filename = "plots/deltas/$(problem_name)_delta_comparison.png"
        savefig(delta_comparison_plot, filename)
        println("Gráfico comparativo de deltas salvo como '$filename'")
    end

    return p
end

"""
    create_delta_comparison_plot(problem_name::Symbol, deltas::Vector{T}, final_points_dict::Dict{T, Vector{Vector{T}}})

Cria um gráfico comparativo dos pontos finais obtidos para diferentes valores de delta
em um problema biobjetivo.

# Arguments
- `problem_name::Symbol`: Nome do problema (deve ser um problema biobjetivo)
- `solver_name::String`: Nome do solver
- `deltas::Vector{T}`: Vetor com os valores de delta testados
- `final_points_dict::Dict{T, Vector{Vector{T}}}`: Dicionário onde a chave é o delta e o valor é um vetor de pontos finais (cada ponto é um vetor [f₁, f₂])

# Returns
- `Plots.Plot`: Objeto do gráfico criado

# Note
Esta função é específica para problemas biobjetivos (2 objetivos).
"""
function create_delta_comparison_plot(problem_name::Symbol, solver_name::String, deltas::Vector{T}, final_points_dict::Dict{T, Vector{Vector{T}}}) where T<:Real
    # Verificar se temos pelo menos 2 deltas para comparar
    if length(deltas) < 2
        error("É necessário pelo menos 2 valores de delta para criar uma comparação")
    end
    
    # Verificar se todos os deltas têm dados
    for delta in deltas
        if !haskey(final_points_dict, delta)
            error("Dados não encontrados para delta = $delta")
        end
    end
    
    # Número de cores é o número de deltas
    colors = distinguishable_colors(length(deltas))
    
    p = plot(title="Comparação de Deltas - $problem_name ($solver_name)",
             xlabel="f₁(x)",
             ylabel="f₂(x)",
             legend=:topright,
             grid=true)
    
    for (i, delta) in enumerate(deltas)
        points = final_points_dict[delta]
        
        # Verificar se temos pontos para este delta
        if !isempty(points)
            # Verificar se todos os pontos têm 2 coordenadas (biobjetivo)
            for (j, point) in enumerate(points)
                if length(point) != 2
                    error("Ponto $j para delta $delta tem $(length(point)) coordenadas, mas esperava 2 (problema biobjetivo)")
                end
            end
            
            # Plotar primeiro ponto com legenda
            scatter!(p, [points[1][1]], [points[1][2]], 
                    ms=4, 
                    color=colors[i], 
                    alpha=0.8, 
                    label="δ = $delta")
            
            # Plotar demais pontos sem legenda
            if length(points) > 1
                for point in points[2:end]
                    scatter!(p, [point[1]], [point[2]], 
                            ms=4, 
                            color=colors[i], 
                            alpha=0.8, 
                            label=false)
                end
            end
        else
            println("Aviso: Nenhum ponto encontrado para delta = $delta")
        end
    end
    
    return p
end

"""
    create_single_delta_plot(problem_name::Symbol, delta::T, final_points::Vector{Vector{T}})

Cria um gráfico dos pontos finais obtidos para um único valor de delta
em um problema biobjetivo.

# Arguments
- `problem_name::Symbol`: Nome do problema (deve ser um problema biobjetivo)
- `solver_name::String`: Nome do solver
- `delta::T`: Valor do delta testado
- `final_points::Vector{Vector{T}}`: Vetor de pontos finais (cada ponto é um vetor [f₁, f₂])

# Returns
- `Plots.Plot`: Objeto do gráfico criado

# Note
Esta função é específica para problemas biobjetivos (2 objetivos) e cria um gráfico
simples mostrando a distribuição dos pontos finais para um único valor de delta.
"""
function create_single_delta_plot(problem_name::Symbol, solver_name::String, delta::T, final_points::Vector{Vector{T}}) where T<:Real
    # Verificar se temos pontos para plotar
    if isempty(final_points)
        error("Nenhum ponto final fornecido para plotagem")
    end
    
    # Verificar se todos os pontos têm 2 coordenadas (biobjetivo)
    for (j, point) in enumerate(final_points)
        if length(point) != 2
            error("Ponto $j tem $(length(point)) coordenadas, mas esperava 2 (problema biobjetivo)")
        end
    end
    
    # Converter pontos para arrays separados para facilitar o plot
    f1_vals = [point[1] for point in final_points]
    f2_vals = [point[2] for point in final_points]
    
    # Criar o gráfico
    p = scatter(f1_vals, f2_vals,
                ms=4, 
                color=:cornflowerblue, 
                alpha=0.8,
                label="δ = $delta",
                xlabel="f₁(x)",
                ylabel="f₂(x)",
                title="Pontos Finais - $problem_name ($solver_name, δ = $delta)",
                grid=true)
    
    # Adicionar estatísticas no gráfico
    n_points = length(final_points)
    p = annotate!(p, 0.02, 0.98, text("Total de pontos: $n_points", 10, :left, :top))
    
    return p
end

"""
    save_single_delta_plot(problem_name::Symbol, delta::T, final_points::Vector{Vector{T}}, filepath::String)

Cria e salva um gráfico dos pontos finais para um único valor de delta.

# Arguments
- `problem_name::Symbol`: Nome do problema
- `solver_name::String`: Nome do solver
- `delta::T`: Valor do delta testado
- `final_points::Vector{Vector{T}}`: Vetor de pontos finais
- `filepath::String`: Caminho do arquivo JLD2 de origem (para nomear o arquivo de saída)

# Returns
- `String`: Caminho do arquivo salvo

# Note
Esta função cria o gráfico e o salva no diretório `data/plots/comparison/PROBLEMA/` com um nome
baseado no solver, delta e arquivo de origem.
"""
function save_single_delta_plot(problem_name::Symbol, solver_name::String, delta::T, final_points::Vector{Vector{T}}, filepath::String) where T<:Real
    println("\n=== Criando plot para problema: $problem_name, solver: $solver_name com δ = $delta ===")
    
    # Verificar se temos pontos para plotar
    if isempty(final_points)
        println("Aviso: Nenhum ponto encontrado para delta = $delta")
        return ""
    end
    
    # Criar o plot
    println("Criando plot...")
    p = create_single_delta_plot(problem_name, solver_name, delta, final_points)
    
    # Preparar nome do arquivo
    delta_str = replace(string(delta), "." => "-")
    filename_base = replace(basename(filepath), ".jld2" => "")
    
    # Criar diretório de saída organizado por problema
    problem_str = string(problem_name)
    output_dir = datadir("plots", "comparison", problem_str)
    mkpath(output_dir)
    
    # Salvar o plot (sem problem_name no nome do arquivo)
    output_file = joinpath(output_dir, "single_delta_$(solver_name)_delta_$(delta_str)_$(filename_base).png")
    savefig(p, output_file)
    println("Plot salvo em: $output_file")
    
    return output_file
end