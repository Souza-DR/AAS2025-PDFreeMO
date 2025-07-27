using DrWatson
@quickactivate "AAS2025-DFreeMO"
using JLD2
using BenchmarkProfiles
using Plots
using Statistics
using Printf

# Incluir o módulo para ter acesso aos tipos e funções de análise
include(srcdir("AAS2025DFreeMO.jl"))
using .AAS2025DFreeMO

# ========================================================================================
# CONFIGURAÇÃO
# ========================================================================================

# Nomes dos solvers (deve corresponder aos nomes salvos no JLD2)
const SOLVER_NAMES = ["DFreeMO", "ProxGrad", "CondG"]

# Métricas disponíveis para análise
const METRICS = Dict(
    "iter" => "Número de iterações",
    "n_f_evals" => "Avaliações de função", 
    "n_Jf_evals" => "Avaliações de gradiente",
    "total_time" => "Tempo de execução (s)"
)

# ========================================================================================
# FUNÇÕES AUXILIARES
# ========================================================================================

# Função list_jld2_files agora importada do módulo AAS2025DFreeMO

"""
Extrai dados de performance de um arquivo JLD2 para criar a matriz de performance
"""
function extract_performance_data(filepath::String, metric::String)
    println("\nExtraindo dados de performance do arquivo: $(basename(filepath))")
    println("Métrica: $(METRICS[metric])")
    
    # Verificar se a métrica é válida
    if !haskey(METRICS, metric)
        println("Métrica inválida. Use uma das seguintes: $(keys(METRICS))")
        return nothing, nothing
    end
    
    # Usar a função do módulo para extrair dados
    return AAS2025DFreeMO.extract_performance_data(filepath, metric, SOLVER_NAMES)
end

"""
Cria e salva o performance profile
"""
function create_performance_profile(filepath::String, metric::String)
    # Extrair todos os dados de uma vez
    perf_matrix, instance_info = extract_performance_data(filepath, metric)
    
    if perf_matrix === nothing || isempty(perf_matrix)
        println("Não foi possível extrair dados de performance.")
        return
    end

    # Encontrar deltas únicos a partir das informações das instâncias
    unique_deltas = unique([info[2] for info in instance_info])
    println("\nDeltas encontrados: $unique_deltas. Gerando um perfil para cada um.")
    
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

        # Verificar se temos dados válidos para este delta
        if all(isnan, perf_matrix_for_delta)
            println("Nenhum dado válido encontrado para a métrica '$metric' com delta = $delta.")
            continue
        end
        
        # Imprimir estatísticas para o delta atual
        println("Estatísticas para delta=$delta, métrica='$(METRICS[metric])':")
        for (solver_idx, solver) in enumerate(SOLVER_NAMES)
            if solver_idx <= size(perf_matrix_for_delta, 2)
                valid_values = filter(!isnan, perf_matrix_for_delta[:, solver_idx])
                if !isempty(valid_values)
                    println("$solver: Min=$(minimum(valid_values)), Max=$(maximum(valid_values)), Média=$(round(mean(valid_values), digits=2)), Mediana=$(round(median(valid_values), digits=2))")
                else
                    println("$solver: Sem valores válidos para este delta")
                end
            end
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
        
        # Criar o gráfico
        delta_str_title = replace(string(delta), ".0" => "")
        title_text = "Performance Profile - $(METRICS[metric]) (δ = $delta_str_title)"
        
        p = performance_profile(PlotsBackend(), perf_matrix_filtered, solvers_with_data, title=title_text)
        
        # Criar estrutura de pastas organizadas por delta
        delta_str_folder = replace(string(delta), "." => "-")
        output_dir = datadir("plots", delta_str_folder)
        mkpath(output_dir)
        
        # Salvar o gráfico (sem delta no nome do arquivo)
        filename_base = replace(basename(filepath), ".jld2" => "")
        output_file = joinpath(output_dir, "perf_profile_$(metric)_$(filename_base).png")
        savefig(p, output_file)
        println("Performance profile para δ=$delta salvo em: $output_file")
    end
end

"""
Cria performance profiles para todas as métricas disponíveis
"""
function create_all_performance_profiles(filepath::String)
    println("\n=== Gerando Performance Profiles para todas as métricas ===")
    
    for (metric, description) in METRICS
        println("\n--- Processando métrica: $metric ($description) ---")
        create_performance_profile(filepath, metric)
    end
    
    println("\n=== Todos os Performance Profiles foram gerados ===")
end

# ========================================================================================
# FUNÇÃO PRINCIPAL
# ========================================================================================

function main()
    println("=== Gerador de Performance Profiles ===")
    println("Usando dados JLD2 do repositório AAS2025-DFreeMO")
    
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
        create_performance_profile(filepath, selected_metric)
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