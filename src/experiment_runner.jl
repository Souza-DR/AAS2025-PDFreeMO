using Dates
using Random # Adicionado para gerar nomes de arquivos temporários únicos

"""
Gera todas as configurações de experimentos com identificadores únicos por delta.

# Arguments
- `problems`: Lista de problemas a serem testados
- `solvers`: Lista de solvers a serem testados  
- `nrun`: Número de execuções por combinação (problema, solver, delta)
- `deltas`: Lista de valores de delta a serem testados
- `common_options`: Opções comuns para todos os solvers
- `solver_specific_options`: Opções específicas por solver (opcional)

# Returns
- `Vector{ExperimentConfig{T}}`: Lista de configurações de experimentos

# Note
Cada configuração recebe um `run_id` único dentro de cada combinação (problema, solver, delta),
garantindo que não haja conflitos na estrutura de dados hierárquica.
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

                for (trial_idx, x0) in enumerate(initial_points)
                    config = ExperimentConfig(
                        solver_sym,
                        problem_sym,
                        trial_idx,  # run_id único dentro de cada (problema, solver, delta)
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
Salva um vetor de resultados em um arquivo JLD2.
Função interna para ser usada por `save_final_results` e salvamento em lote.
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
Copia recursivamente o conteúdo de um grupo JLD2 de origem para um destino.
"""
function _copy_jld2_contents(source::Union{JLD2.Group, JLD2.JLDFile}, dest::Union{JLD2.Group, JLD2.JLDFile})
    for key in keys(source)
        if JLD2.haskey(dest, key)
            obj_source = source[key]
            obj_dest = dest[key]
            
            if obj_source isa JLD2.Group && obj_dest isa JLD2.Group
                _copy_jld2_contents(obj_source, obj_dest)
            else
                println("Aviso: A chave '$key' causou um conflito. Sobrescrevendo o destino.")
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
Anexa resultados de um arquivo JLD2 temporário para um arquivo final.
"""
function append_from_jld2(final_filepath::String, temp_filepath::String)
    jldopen(final_filepath, "a+") do final_file
        jldopen(temp_filepath, "r") do temp_file
            _copy_jld2_contents(temp_file, final_file)
        end
    end
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
        if config.solver_name == :PDFPM
            if config.problem_name == :AAS1 || config.problem_name == :AAS2
                # Executar o solver usando as matrizes pré-computadas
                result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                        config.data_matrices,
                                        config.delta,
                                        config.initial_point,
                                        options;
                                        lb = l, ub = u)
            else
                # Executar o solver usando as matrizes pré-computadas
                result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                        config.data_matrices,
                                        config.delta,
                                        config.initial_point,
                                        options; evalJf = x -> safe_evalJf_solver(problem_instance, x),
                                        lb = l, ub = u)
            end
            
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
                copy(result.F_init),
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
Executa experimentos com salvamento em lotes para evitar perda de dados.

# Arguments
- `configs`: Vetor de configurações de experimentos.
- `batch_size`: Número de resultados a serem salvos em cada lote.
- `filename_base`: Nome base para o arquivo de resultados "vivo".

# Returns
- `Vector{ExperimentResult{T}}`: Vetor com todos os resultados coletados.
"""
function run_experiment_with_batch_saving(
    configs::Vector{ExperimentConfig{T}};
    batch_size::Int = 50,
    filename_base::String = "benchmark_live"
) where T
    all_results = ExperimentResult{T}[]
    
    if length(configs) <= batch_size
        println("Total de experimentos ($(length(configs))) não é maior que o tamanho do lote ($batch_size). Nenhum salvamento em lote ocorrerá.")
        for config in configs
            result = run_single_experiment(config)
            push!(all_results, result)
        end
        _save_results_to_jld2(datadir("sims", "$(filename_base).jld2"), all_results)
        return all_results
    end

    current_batch = ExperimentResult{T}[]
    final_filepath = datadir("sims", "$(filename_base).jld2")
    
    println("Salvamento em lote ativado. Resultados intermediários serão salvos em: $final_filepath")
    mkpath(datadir("sims"))

    for (i, config) in enumerate(configs)
        result = run_single_experiment(config)
        push!(all_results, result)
        push!(current_batch, result)

        if length(current_batch) >= batch_size || i == length(configs)
            println("\nProcessando lote. Salvando $(length(current_batch)) resultados...")
            
            temp_filename = "temp_batch_$(randstring(8)).jld2"
            temp_filepath = joinpath(datadir("sims"), temp_filename)
            
            try
                _save_results_to_jld2(temp_filepath, current_batch)
                println("Lote temporário salvo em: $temp_filepath")

                append_from_jld2(final_filepath, temp_filepath)
                println("Lote anexado a: $final_filepath")
            finally
                if isfile(temp_filepath)
                    rm(temp_filepath)
                    println("Arquivo temporário removido.")
                end
            end
            
            empty!(current_batch)
        end
    end

    println("\nExecução de experimentos em lote concluída.")
    return all_results
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
        fill(T(NaN), nobj),
        fill(T(NaN), nobj)
    )
end

function run_experiment(configs::Vector{ExperimentConfig{T}}) where T
    all_results = ExperimentResult{T}[]
    
    println("Executando $(length(configs)) experimentos")
    
    for config in configs
        result = run_single_experiment(config)
        # Adicionar aos resultados totais
        push!(all_results, result)
    end
    
    return all_results
end