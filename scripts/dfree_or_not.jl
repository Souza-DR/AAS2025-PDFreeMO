using DrWatson
using MOProblems
using MOSolvers
using Random
using Dates
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO


const SOLVERS = [:Dfree, :PDFPM] 
const NRUN = 50
const DELTAS = [0.0, 0.1]
# all_list = [Symbol(p) for p in sort(MOProblems.filter_problems(has_jacobian=true))]
all_list = [Symbol(p) for p in sort(MOProblems.get_problem_names())]
const PROBLEMS = all_list
# ========================================================================================
# --- CONFIGURAÇÃO CENTRALIZADA DOS SOLVERS ---
# ========================================================================================

# Configurar parâmetros COMUNS a todos os solvers em um só lugar
const COMMON_SOLVER_OPTIONS = CommonSolverOptions(
    verbose = 1,                    # Sem saída detalhada para benchmark
    max_iter = 100,                # Máximo de iterações
    opt_tol = 1e-4,                # Tolerância de otimalidade
    ftol = 1e-4,                   # Tolerância da função
    max_time = 3600.0,             # Tempo máximo em segundos
    print_interval = 1,           # Intervalo de impressão
    store_trace = false,           # Não armazenar trace para economizar memória
    stop_criteria = :pdfpm # Critério de parada padrão
)

# Configurar parâmetros ESPECÍFICOS por solver (opcional)
const SOLVER_SPECIFIC_OPTIONS = Dict{Symbol, SolverSpecificOptions{Float64}}(
    :PDFPM => SolverSpecificOptions(
        max_subproblem_iter = 20, epsilon = 1e-4, sigma = 1.0,   # Reduzir iterações do subproblema para benchmark
        # epsilon, sigma, alpha usarão valores padrão
    )
)

function run_experiment(config::ExperimentConfig{T}) where T
    problem_constructor = getfield(MOProblems, config.problem_name)
    problem_instance = problem_constructor()

    # Obter opções do solver
    options = get_solver_options(config.solver_name, config.solver_config)
       
    l, u = problem_instance.bounds
        
    # Obter a função do solver e suas opções
    solver_function = getfield(MOSolvers, :PDFPM)

    try        
        if config.solver_name == :PDFPM
            # Executar o solver usando as matrizes pré-computadas
            result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                     config.data_matrices,
                                     config.delta,
                                     config.initial_point,
                                     options; evalJf = x -> safe_evalJf_solver(problem_instance, x),
                                     lb = l, ub = u)
        elseif config.solver_name == :Dfree
            # Executar o solver usando as matrizes pré-computadas
            result = solver_function(x -> safe_evalf_solver(problem_instance, x),
                                     config.data_matrices,
                                     config.delta,
                                     config.initial_point,
                                     options;
                                     lb = l, ub = u)
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
            return AAS2025PDFreeMO.create_failed_result(config, problem_instance.nobj)
        end
        
    catch e
        # Ocorreu um erro durante a execução do solver
        @warn "Erro ao executar $(config.solver_name) no problema $(config.problem_name) (run_id=$(config.run_id), delta=$(config.delta)): $e"
        return AAS2025PDFreeMO.create_failed_result(config, problem_instance.nobj)
    end
end

function run_with_batch_saving(
    configs::Vector{ExperimentConfig{T}};
    batch_size::Int = 50,
    filename_base::String = "Dfree_or_not"
) where T
    all_results = ExperimentResult{T}[]
    
    if length(configs) <= batch_size
        println("Total de experimentos ($(length(configs))) não é maior que o tamanho do lote ($batch_size). Nenhum salvamento em lote ocorrerá.")
        for config in configs
            result = run_experiment(config)
            push!(all_results, result)
        end
        AAS2025PDFreeMO._save_results_to_jld2(datadir("sims", "$(filename_base).jld2"), all_results)
        return all_results
    end

    current_batch = ExperimentResult{T}[]
    final_filepath = datadir("sims", "$(filename_base).jld2")
    
    println("Salvamento em lote ativado. Resultados intermediários serão salvos em: $final_filepath")
    mkpath(datadir("sims"))

    for (i, config) in enumerate(configs)
        result = run_experiment(config)
        push!(all_results, result)
        push!(current_batch, result)

        if length(current_batch) >= batch_size || i == length(configs)
            println("\nProcessando lote. Salvando $(length(current_batch)) resultados...")
            
            temp_filename = "temp_batch_$(randstring(8)).jld2"
            temp_filepath = joinpath(datadir("sims"), temp_filename)
            
            try
                AAS2025PDFreeMO._save_results_to_jld2(temp_filepath, current_batch)
                println("Lote temporário salvo em: $temp_filepath")

                AAS2025PDFreeMO.append_from_jld2(final_filepath, temp_filepath)
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

function main()
    Random.seed!(42)
    
    println("Iniciando benchmark com $(length(PROBLEMS)) problemas")
    println("Solvers: $(length(SOLVERS)), Execuções: $NRUN, Deltas: $DELTAS")
    println("Opções comuns: max_iter=$(COMMON_SOLVER_OPTIONS.max_iter), opt_tol=$(COMMON_SOLVER_OPTIONS.opt_tol)")
    
    # Gerar configurações de experimentos com as novas opções padronizadas
    configs = AAS2025PDFreeMO.generate_experiment_configs(
        PROBLEMS, 
        SOLVERS, 
        NRUN, 
        DELTAS, 
        COMMON_SOLVER_OPTIONS;
        solver_specific_options = SOLVER_SPECIFIC_OPTIONS
    )
    println("Total de experimentos: $(length(configs))")
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    
    # Executar com salvamento em lote para evitar perda de dados
    results = run_with_batch_saving(
        configs,
        batch_size=50,
        filename_base="Dfree_or_not_$(timestamp)"
    )
    
    println("\nBenchmark concluído! Resultados salvos em: $(datadir("sims"))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
