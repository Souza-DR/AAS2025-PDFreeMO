using DrWatson
using MOProblems
using MOSolvers
using Random
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# --- CONFIGURAÇÃO CENTRALIZADA DOS SOLVERS ---
# ========================================================================================

# Configurar parâmetros COMUNS a todos os solvers em um só lugar
const COMMON_SOLVER_OPTIONS = CommonSolverOptions(
    verbose = 1,                    # Sem saída detalhada para benchmark
    max_iter = 100,                # Máximo de iterações
    opt_tol = 1e-6,                # Tolerância de otimalidade
    ftol = 1e-4,                   # Tolerância da função
    max_time = 3600.0,             # Tempo máximo em segundos
    print_interval = 1,           # Intervalo de impressão
    store_trace = false,           # Não armazenar trace para economizar memória
    stop_criteria = :proxgrad      # Critério de parada padrão
)

# Configurar parâmetros ESPECÍFICOS por solver (opcional)
const SOLVER_SPECIFIC_OPTIONS = Dict{Symbol, SolverSpecificOptions{Float64}}(
    :DFreeMO => SolverSpecificOptions(
        max_subproblem_iter = 50,   # Reduzir iterações do subproblema para benchmark
        # epsilon, sigma, alpha usarão valores padrão
    ),
    :ProxGrad => SolverSpecificOptions(
        mu = 1.0                    # Usar valor padrão explicitamente
    )
    # :CondG => SolverSpecificOptions()  # Nenhum parâmetro específico, pode omitir
)

# Outras configurações do benchmark
const SOLVERS = [:DFreeMO, :ProxGrad, :CondG] # Usar símbolos para os solvers
# const SOLVERS = [:CondG] # Usar símbolos para os solvers
const NRUN = 200
const DELTAS = [0.0, 0.02, 0.05, 0.1]
# const DELTAS = [0.02]
# Usar símbolos para os nomes dos problemas
BI_list = [Symbol(p) for p in MOProblems.filter_problems(min_objs=2, max_objs=2)]
const PROBLEMS = BI_list
# const PROBLEMS = [BI_list[2]]  # Criar uma lista com 1 elemento
# const PROBLEMS = ["AP2"]

println("Problemas selecionados: $PROBLEMS")


function main()
    Random.seed!(42)
    
    println("Iniciando benchmark com $(length(PROBLEMS)) problemas")
    println("Solvers: $(length(SOLVERS)), Execuções: $NRUN, Deltas: $DELTAS")
    println("Opções comuns: max_iter=$(COMMON_SOLVER_OPTIONS.max_iter), opt_tol=$(COMMON_SOLVER_OPTIONS.opt_tol)")
    
    # Gerar configurações de experimentos com as novas opções padronizadas
    configs = AAS2025DFreeMO.generate_experiment_configs(
        PROBLEMS, 
        SOLVERS, 
        NRUN, 
        DELTAS, 
        COMMON_SOLVER_OPTIONS;
        solver_specific_options = SOLVER_SPECIFIC_OPTIONS
    )
    println("Total de experimentos: $(length(configs))")

    # Executar com salvamento em lote para evitar perda de dados
    results = AAS2025DFreeMO.run_experiment_with_batch_saving(
        configs,
        batch_size=50,
        filename_base="benchmark_live_biobjective"
    )
    
    println("\nBenchmark concluído! Resultados salvos em: $(datadir("sims"))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
