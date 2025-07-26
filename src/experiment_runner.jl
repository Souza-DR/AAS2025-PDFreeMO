using Dates

"""
Gera todas as configurações de experimentos
"""
function generate_experiment_configs(problems, solvers, nrun, deltas, common_options::CommonSolverOptions{T}; solver_specific_options::Dict{Symbol, SolverSpecificOptions{T}} = Dict{Symbol, SolverSpecificOptions{T}}()) where T
    configs = ExperimentConfig{T}[]

    for problem_name in problems
        # Garantir que problem_name seja Symbol
        problem_sym = isa(problem_name, Symbol) ? problem_name : Symbol(problem_name)

        problem_constructor = getfield(MOProblems, problem_sym)
        problem_instance = problem_constructor()

        # Gerar pontos iniciais para este problema
        n = problem_instance.nvar
        l, u = problem_instance.bounds
        initial_points = [l + rand(n) .* (u - l) for _ in 1:nrun]

        # Para cada delta, pré-computar uma única matriz A a ser partilhada por todos os solvers
        for delta in deltas
            data_matrices = datas(n, problem_instance.nobj, delta)  # Fixa A para este (problema, δ)

            for solver in solvers
                # Garantir que solver_name seja Symbol
                solver_sym = isa(solver, Symbol) ? solver : Symbol(string(solver))

                # Obter opções específicas para este solver, ou usar padrão vazio
                specific_opts = get(solver_specific_options, solver_sym, SolverSpecificOptions{T}())
                solver_config = SolverConfiguration(common_options, specific_opts)

                for (trial_id, x0) in enumerate(initial_points)
                    config = ExperimentConfig(
                        solver_sym,
                        problem_sym,
                        trial_id,
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
Executa um experimento individual
"""
function run_single_experiment(config::ExperimentConfig{T}) where T
    problem_constructor = getfield(MOProblems, config.problem_name)
    problem_instance = problem_constructor()

    # Obter opções do solver
    options = get_solver_options(config.solver_name, config.solver_config)
       
    l, u = problem_instance.bounds
        
    # Obter a função do solver e suas opções
    solver_function = getfield(MOSolvers, config.solver_name)

    try        
        if config.solver_name == :DFreeMO
            # Executar o solver usando as matrizes pré-computadas
            result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                     config.data_matrices,
                                     config.delta,
                                     config.initial_point,
                                     options;
                                     lb = l, ub = u)
        elseif config.solver_name == :ProxGrad || config.solver_name == :CondG
            # Executar o solver usando as matrizes pré-computadas
            result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                     x -> safe_evalJf_solver(problem_instance, x),
                                     config.data_matrices,
                                     config.delta,
                                     config.initial_point,
                                     options;
                                     lb = l, ub = u)
            println("Mensagem do solver: ", result.message)
        else
            error("Solver $(config.solver_name) não suportado")
        end

        # Checar se o solver retornou um resultado bem-sucedido
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
                copy(result.Fval)
            )
            return res
        else
            # O solver terminou a execução mas não obteve sucesso
            return create_failed_result(config, problem_instance.nobj)
        end
        
    catch e
        # Ocorreu um erro durante a execução do solver
        return create_failed_result(config, problem_instance.nobj)
    end
end

"""
Cria resultado para experimento que falhou
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
        fill(T(NaN), nobj)
    )
end

function run_experiment(configs::Vector{ExperimentConfig{T}}) where T
    all_results = ExperimentResult{T}[]
    
    println("Executando $(length(configs)) experimentos")
    
    for config in configs
        result = run_single_experiment(config)
        if !result.success
            println("result.success Linha 139: ", result.success)
            # exit(1)
        end
        # Adicionar aos resultados totais
        push!(all_results, result)
    end
    
    return all_results
end

"""
Salva um vetor de resultados de experimentos em um arquivo JLD2,
organizando os dados de forma hierárquica.

A estrutura de salvamento segue o padrão:
`solver_name / problem_name / run_id`

# Arguments
- `results::Vector{<:ExperimentResult}`: Vetor com os resultados dos experimentos.
- `filename_base::String`: Nome base para o arquivo de saída (sem extensão).
"""
function save_final_results(results::Vector{<:ExperimentResult}, filename_base::String)
    # Garantir que o diretório de simulações exista
    mkpath(datadir("sims"))
    
    # Gerar timestamp para o nome do arquivo
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    
    # Construir o caminho completo do arquivo com timestamp
    filepath = datadir("sims", "$(filename_base)_$(timestamp).jld2")
    
    println("Salvando $(length(results)) resultados em: $filepath")
    
    # Abrir o arquivo JLD2 em modo de "w" (write/overwrite) para evitar conflitos
    jldopen(filepath, "w") do file
        for result in results
            # Criar a chave hierárquica para o resultado
            key = "$(result.solver_name)/$(result.problem_name)/run_$(result.run_id)"
            
            # Salvar o objeto de resultado diretamente com a chave hierárquica
            # O JLD2 criará os grupos intermediários (solver/problema) automaticamente
            file[key] = result
        end
    end
    
    println("Salvamento concluído.")
end