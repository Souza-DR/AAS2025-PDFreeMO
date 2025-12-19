using DrWatson
@quickactivate "AAS2025-PDFreeMO"
using JLD2
using BenchmarkProfiles
using Statistics
using Printf
using Plots
using PlotThemes

# Incluir o módulo para ter acesso aos tipos e funções de análise
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# CONFIGURAÇÃO
# ========================================================================================

# Nomes dos solvers (deve corresponder aos nomes salvos no JLD2)
const SOLVER_NAMES = ["PDFPM", "CondG", "ProxGrad"]

# Métricas disponíveis para análise
const METRICS = Dict(
    "iter" => "Iterations",
    "n_f_evals" => "Function evaluations",
    "n_Jf_evals" => "Gradient evaluations",
    "total_time" => "Execution time (s)"
)

# ========================================================================================
# FUNÇÕES AUXILIARES
# ========================================================================================

"""
Cria e salva o performance profile
"""
function create_performance_profile(filepath::String, metric::String)
    perf_matrix, instance_info = AAS2025PDFreeMO.extract_performance_data(filepath, metric, SOLVER_NAMES)
    
    if perf_matrix === nothing || isempty(perf_matrix)
        println("Não foi possível extrair dados de performance.")
        return Dict{Float64, Dict{Symbol, String}}()
    end

    # Filtrar problemas que nao foram resolvidos por nenhum dos solvers
    valid_rows = []
    # valid_rows = findall(row -> !all(isnan, row) , eachrow(perf_matrix))
    valid_rows = findall(row -> !all(isnan, row) && !any(==(0.0), row), eachrow(perf_matrix))


    println("Total de instâncias: $(size(perf_matrix, 1)), Válidas: $(length(valid_rows))")
    
    # Criar um PP para todos os deltas simnultaneamente
    # Preparar nome do arquivo
    filename_base = replace(basename(filepath), ".jld2" => "")
    output_name = "pp_$(metric)_$(filename_base)"
    title_text = "$(METRICS[metric])"

    # Criar o gráfico
    # default(
    #         fontfamily    = "Computer Modern",  # or "Times New Roman", "Arial", etc.
    #         guidefontsize = 14,
    #         tickfontsize  = 12,
    #         legendfontsize= 12,
    #     )
    p = performance_profile(
            PlotsBackend(),
            perf_matrix[valid_rows, :], SOLVER_NAMES;
            title     = title_text,
            xlabel    = "Performance Ratio",
            ylabel    = "Solved Problems",
            lw        = 3,
            palette   = [:red, :blue, :green],
            linestyles= [:solid :dash :dot :dashdot],
            legend    = :bottomright,
            grid      = :none,
            framestyle= :box,
            # size      = (1200, 800),
            sampletol = 1e-4
        )

    base_dir = datadir("plots", "PP")
    pdf_dir = joinpath(base_dir, "pdf")
    mkpath(pdf_dir)
    output_file = joinpath(pdf_dir, "$(output_name).pdf")
    savefig(p, output_file)
    println("Performance profile salvo em: $output_file")
    # Encontrar deltas únicos a partir das informações das instâncias
    unique_deltas = unique([info[2] for info in instance_info])
    println("\nDeltas encontrados: $unique_deltas. Gerando um perfil para cada um.")
    
    all_saved_files = Dict{Float64, Dict{Symbol, String}}()
    
    # Iterar sobre cada delta e criar um perfil de desempenho
    for delta in unique_deltas
        println("\n--- Processando Delta = $delta ---")
        
        # Filtrar a matriz de performance e as informações de instância para o delta atual
        indices = findall(info -> info[2] == delta, instance_info)
        
        if isempty(indices)
            println("Nenhuma instância encontrada para o delta $delta.")
            continue
        end
        
        perf_matrix_for_delta = perf_matrix[indices, :]
        # valid_rows = findall(row -> !all(isnan, row) , eachrow(perf_matrix_for_delta))
        valid_rows = findall(row -> !all(isnan, row) && !any(==(0.0), row), eachrow(perf_matrix_for_delta))

        perf_matrix_for_delta = perf_matrix_for_delta[valid_rows, :]

        # Verificar se temos dados válidos para este delta
        if all(isnan, perf_matrix_for_delta)
            println("Nenhum dado válido encontrado para a métrica '$metric' com delta = $delta.")
            continue
        end
        
        # Filtrar solvers que têm dados para este delta
        solvers_with_data = String[]
        valid_cols = []
        for (solver_idx, solver) in enumerate(SOLVER_NAMES)
            if solver_idx <= size(perf_matrix_for_delta, 2) && !all(isnan, perf_matrix_for_delta[:, solver_idx])
                push!(solvers_with_data, String(solver))
                push!(valid_cols, solver_idx)
            end
        end
        
        if length(solvers_with_data) < 2
            println("São necessários pelo menos 2 solvers com dados válidos para criar o perfil para delta = $delta.")
            continue
        end
        
        perf_matrix_filtered = perf_matrix_for_delta[:, valid_cols]
        
        # Criar estrutura de pastas organizadas por delta
        delta_str_folder = replace(string(delta), "." => "-")
        base_dir = datadir("plots", "PP", delta_str_folder)
        
        # Preparar nome do arquivo
        filename_base = replace(basename(filepath), ".jld2" => "")
        output_name = "pp_$(metric)_$(filename_base)"

        title_text = "$(METRICS[metric]) (δ = $delta)"
    
        # # Criar o gráfico
        # default(
        #         fontfamily    = "Computer Modern",  # or "Times New Roman", "Arial", etc.
        #         guidefontsize = 14,
        #         tickfontsize  = 12,
        #         legendfontsize= 12,
        #     )
        p = performance_profile(
                PlotsBackend(),
                perf_matrix_filtered, SOLVER_NAMES;
                title     = title_text,
                xlabel    = "Performance Ratio",
                ylabel    = "Solved Problems",
                lw        = 3,
                palette   = [:red, :blue, :green],
                linestyles= [:solid :dash :dot :dashdot],
                legend    = :bottomright,
                grid      = :none,
                framestyle= :box,
                sampletol = 1e-4
            )
        
        pdf_dir = joinpath(base_dir, "pdf")
        mkpath(pdf_dir)
        output_file = joinpath(pdf_dir, "$(output_name).pdf")
        savefig(p, output_file)
        all_saved_files[delta] = Dict(:pdf => output_file)
        println("Performance profile salvo em: $output_file")
    end
    
    return all_saved_files
end

"""
Cria performance profiles para todas as métricas disponíveis
"""
function create_all_performance_profiles(filepath::String)
    println("\n=== Gerando Performance Profiles para todas as métricas ===")
    
    all_results = Dict{String, Any}()
    
    for (metric, description) in METRICS
        println("\n--- Processando métrica: $metric ($description) ---")
        results = create_performance_profile(filepath, metric)
        all_results[metric] = results
    end
    
    println("\n=== Todos os Performance Profiles foram gerados ===")
    
    return all_results
end

# ========================================================================================
# FUNÇÃO PRINCIPAL
# ========================================================================================

function main()
    println("=== Gerador de Performance Profiles ===")
    println("Usando dados JLD2 do repositório AAS2025-PDFreeMO")
    
    # Listar arquivos disponíveis
    jld2_files = list_jld2_files()

    
    
    if isempty(jld2_files)
        return
    end
    
    # Escolher arquivo
    if length(jld2_files) == 1
        selected_file = jld2_files[1]
        println("\nUsando arquivo: $selected_file")
    else
        println("\nEscolha um arquivo para analisar:")
        for (i, file) in enumerate(jld2_files)
            println("$i. $file")
        end
        
        print("Digite o número do arquivo: ")
        choice = parse(Int, readline())
        
        if 1 <= choice <= length(jld2_files)
            selected_file = jld2_files[choice]
        else
            println("Escolha inválida.")
            return
        end
    end
    
    # Escolher métrica
    println("\nEscolha a métrica para o performance profile:")
    for (i, (metric, description)) in enumerate(METRICS)
        println("$i. $metric ($description)")
    end
    println("$(length(METRICS) + 1). Todas as métricas")
    
    print("Digite o número da métrica: ")
    metric_choice = parse(Int, readline())
    
    metrics_list = collect(keys(METRICS))
    if 1 <= metric_choice <= length(metrics_list)
        selected_metric = metrics_list[metric_choice]
        # Criar o performance profile para uma métrica específica
        filepath = datadir("sims", selected_file)
        results = create_performance_profile(filepath, selected_metric)
        
        # Mostrar diretórios de saída
        for delta in keys(results)
            delta_str = replace(string(delta), "." => "-")
            base_dir = datadir("plots", "PP", delta_str, "pdf")
            println("\nDiretório de saída para delta = $delta:")
            if isdir(base_dir)
                println("  - PDF: $base_dir")
            end
        end
        
    elseif metric_choice == length(metrics_list) + 1
        # Criar performance profiles para todas as métricas
        filepath = datadir("sims", selected_file)
        create_all_performance_profiles(filepath)
    else
        println("Escolha inválida.")
        return
    end
    
    println("\nAnálise concluída!")
end

# Executar se o script for chamado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 