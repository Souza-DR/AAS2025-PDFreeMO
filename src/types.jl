"""
    ExperimentResult

Armazena os parâmetros de entrada e os resultados de uma única execução 
de um solver em um problema de otimização.

# Fields
- `solver_name::Symbol`: Nome do solver utilizado.
- `problem_name::Symbol`: Nome do problema otimizado.
- `run_id::Int`: Identificador da execução (e.g., de 1 a 200 para cada ponto inicial).
- `delta::T`: Valor do parâmetro de robustez delta.
- `initial_point::Vector{T}`: Ponto inicial utilizado.
- `success::Bool`: true` se o solver executou e retornou um resultado com sucesso, `false` caso contrário
- `iter::Int`: Número total de iterações que o solver executou.
- `n_f_evals::Int`: Número total de avaliações da função objetivo.
- `n_Jf_evals::Int`: Número total de avaliações do Jacobiano (gradientes).
- `total_time::Float64`: Tempo de execução em segundos.
- `F_init::Vector{T}`: Vetor com o valor inicial da função objetivo.
- `final_objective_value::Vector{T}`: Vetor com o valor final da função objetivo.

"""
struct ExperimentResult{T<:Real}
    # Parâmetros de entrada da instância
    solver_name::Symbol
    problem_name::Symbol
    run_id::Int
    delta::T
    initial_point::Vector{T}

    # Métricas de resultado
    success::Bool
    iter::Int
    n_f_evals::Int
    n_Jf_evals::Int
    total_time::Float64
    F_init ::Vector{T}
    final_objective_value::Vector{T}
end

"""
    ExperimentConfig{T}

Armazena todos os parâmetros necessários para executar uma única instância de um
experimento de forma reprodutível. A struct garante a consistência dos tipos
e a validação dos nomes.

# Fields
- `solver_name::Symbol`: Nome do solver a ser utilizado.
- `problem_name::Symbol`: Nome do problema a ser resolvido.
- `run_id::Int`: Identificador numérico da execução (ex: de 1 a 100).
- `delta::T`: Valor do parâmetro de robustez.
- `initial_point::Vector{T}`: Ponto inicial para a otimização.
- `solver_config::SolverConfiguration{T}`: Objeto contendo as configurações (comuns e específicas) do solver.
- `data_matrices::Vector{Matrix{T}}`: Coleção de matrizes `A` pré-computadas e **fixas** para o par (problema, δ), usadas na parte não diferenciável `H`.
"""
struct ExperimentConfig{T<:Real}
    solver_name::Symbol
    problem_name::Symbol
    run_id::Int
    delta::T
    initial_point::Vector{T}
    solver_config::SolverConfiguration{T}
    # Matrizes de dados A fixas para (problema, δ)
    data_matrices::Vector{Matrix{T}}
    
    # Construtor interno com validação
    function ExperimentConfig{T}(
        solver_name, problem_name, run_id, delta, 
        initial_point, solver_config, data_matrices
    ) where T<:Real
        
        # Garantir que problem_name e solver_name são Symbol
        problem_sym = problem_name isa Symbol ? problem_name : Symbol(string(problem_name))
        solver_sym = solver_name isa Symbol ? solver_name : Symbol(string(solver_name))
        
        # Validar tipos
        delta_val = T(delta)
        run_id_val = Int(run_id)
        initial_point_val = Vector{T}(initial_point)
        data_matrices_val = Vector{Matrix{T}}(data_matrices)
        
        new{T}(solver_sym, problem_sym, run_id_val, delta_val, 
                initial_point_val, solver_config, data_matrices_val)
    end
end

# Construtor externo conveniente
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