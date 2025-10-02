using DrWatson
using MOProblems
using MOSolvers
using Random
using Dates
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
    opt_tol = 1e-4,                # Tolerância de otimalidade
    ftol = 1e-4,                   # Tolerância da função
    max_time = 3600.0,             # Tempo máximo em segundos
    print_interval = 1,           # Intervalo de impressão
    store_trace = false,           # Não armazenar trace para economizar memória
)

# Configurar parâmetros ESPECÍFICOS por solver (opcional)
const SOLVER_SPECIFIC_OPTIONS = Dict{Symbol, SolverSpecificOptions{Float64}}(
    :PDFPM => SolverSpecificOptions(
        max_subproblem_iter = 20, epsilon = 1e-4, sigma = 1.0, # Reduzir iterações do subproblema para benchmark
        # epsilon, sigma, alpha usarão valores padrão
    ),
    :ProxGrad => SolverSpecificOptions(
        mu = 1.0                    # Usar valor padrão explicitamente
    )
    # :CondG => SolverSpecificOptions()  # Nenhum parâmetro específico, pode omitir
)

# Outras configurações do benchmark
const SOLVERS = [:PDFPM, :ProxGrad, :CondG] # Usar símbolos para os solvers
# const SOLVERS = [:PDFPM]
const NRUN = 200
const DELTAS = [0.0, 0.02, 0.05, 0.1]
# all_list = [Symbol(p) for p in sort(MOProblems.filter_problems(has_jacobian=true))]
all_list = [Symbol(p) for p in sort(MOProblems.get_problem_names())]
const PROBLEMS = all_list
println("Problemas selecionados: $PROBLEMS")

function main()
    Random.seed!(42)
    timestamp = Dates.format(now(), "yyyy-mm-dd_HH-MM-SS")
    filename = "all_results_$(timestamp).jld2"
    filepath = joinpath(datadir("sims"), filename)


    println("Iniciando benchmark com $(length(PROBLEMS)) problemas")
    println("Solvers: $(length(SOLVERS)), Execuções: $NRUN, Deltas: $DELTAS")
    println("Opções comuns: max_iter=$(COMMON_SOLVER_OPTIONS.max_iter), opt_tol=$(COMMON_SOLVER_OPTIONS.opt_tol)")

    for problem in PROBLEMS
        # Gerar configurações de experimentos com as novas opções padronizadas
        configs = AAS2025PDFreeMO.generate_experiment_configs(
            [Symbol(problem)], 
            SOLVERS, 
            NRUN, 
            DELTAS, 
            COMMON_SOLVER_OPTIONS;
            solver_specific_options = SOLVER_SPECIFIC_OPTIONS
        )
        println("Total de instâncias para o problema $problem: $(length(configs))")

        # Executar com salvamento em lote para evitar perda de dados
        results = AAS2025PDFreeMO.run_experiment_with_batch_saving(
            configs,
            batch_size=50,
            filename_base="$problem",
        )

        AAS2025PDFreeMO.append_from_jld2(filepath, joinpath(datadir("sims"), "$problem.jld2"))

        mkpath(joinpath(datadir("sims"), "problems"))
        mv(joinpath(datadir("sims"), "$problem.jld2"),
        joinpath(datadir("sims"), "problems", "$problem.jld2"); force=true)

        # --- limpeza de memória ---
        configs = nothing
        results = nothing
        GC.gc()

        println("\nBenchmark concluído! Resultados salvos em: $(datadir("sims"))")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
