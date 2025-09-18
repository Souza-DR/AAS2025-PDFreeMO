using DrWatson
@quickactivate "AAS2025-PDFreeMO"
using JLD2
using BenchmarkProfiles
using CairoMakie  # Usando apenas CairoMakie para formatos vetoriais
using Statistics
using Printf
using Plots

# Incluir o módulo para ter acesso aos tipos e funções de análise
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# CONFIGURAÇÃO
# ========================================================================================

# Nomes dos solvers (deve corresponder aos nomes salvos no JLD2)
const SOLVER_NAMES = ["PDFPM", "ProxGrad", "CondG"]

# Métricas disponíveis para análise
const METRICS = Dict(
    "iter" => "Número de iterações",
    "n_f_evals" => "Avaliações de função", 
    "n_Jf_evals" => "Avaliações de gradiente",
    "total_time" => "Tempo de execução (s)"
)

# Formatos de saída para os gráficos (apenas vetoriais)
const OUTPUT_FORMATS = [:svg, :eps]

# ========================================================================================
# FUNÇÕES AUXILIARES
# ========================================================================================

"""
    save_figure(fig, name::String, base_dir::String; formats=OUTPUT_FORMATS)

Saves the figure in specified formats (SVG, EPS) in separate subdirectories,
with a name based on `name`.

# Arguments
- `fig`: The figure to save
- `name::String`: Base name for the file
- `base_dir::String`: Base directory where format-specific subdirectories will be created
- `formats`: Array of formats to save (e.g., [:svg, :eps])

# Returns
- `Dict{Symbol,String}`: Dictionary mapping formats to saved file paths
"""
function save_figure(fig, name::String, base_dir::String; formats=OUTPUT_FORMATS)
    saved = Dict{Symbol,String}()
    
    for fmt in formats
        # Create format-specific directory
        format_dir = joinpath(base_dir, string(fmt))
        mkpath(format_dir)
        
        # Create filename
        fname = joinpath(format_dir, "$(name).$(fmt)")
        
        try
            save(fname, fig)  # CairoMakie supports SVG, PDF, EPS
            println("✓ Saved $fmt: $fname")
            saved[fmt] = fname
        catch e
            println("✗ Failed to save $fmt for $name: $e")
        end
    end
    
    return saved
end

"""
Cria e salva o performance profile usando CairoMakie
"""
function create_performance_profile(filepath::String, metric::String)
    # Extrair todos os dados de uma vez
    # perf_matrix, instance_info = extract_performance_data(filepath, metric)
    perf_matrix, instance_info = AAS2025PDFreeMO.extract_performance_data(filepath, metric, SOLVER_NAMES)
    
    if perf_matrix === nothing || isempty(perf_matrix)
        println("Não foi possível extrair dados de performance.")
        return Dict{Float64, Dict{Symbol, String}}()
    end

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
        
        # Criar estrutura de pastas organizadas por delta
        delta_str_folder = replace(string(delta), "." => "-")
        base_dir = datadir("plots", delta_str_folder)
        
        # Preparar nome do arquivo
        filename_base = replace(basename(filepath), ".jld2" => "")
        output_name = "perf_profile_$(metric)_$(filename_base)"

        title_text = "Performance Profile - $(METRICS[metric]) (δ = $delta)"
    
        # Criar o gráfico
        p = performance_profile(PlotsBackend(), perf_matrix_filtered, SOLVER_NAMES, title=title_text)
        
        # Salvar o gráfico
        output_file = joinpath(RESULTS_DIR, "perf_profile_$(metric)_$(timestamp).png")
        savefig(p, output_file)
        println("Performance profile salvo em: $output_file")
        
        # Criar e salvar com CairoMakie
        try
            # Criar o gráfico com CairoMakie
            fig = Figure(size=(800, 600))
            ax = Axis(fig[1, 1], 
                     title="Performance Profile - $(METRICS[metric]) (δ = $(replace(string(delta), ".0" => "")))",
                     xlabel="Performance Ratio",
                     ylabel="Fraction of Problems")
            
            # Calcular os dados do perfil de desempenho
            T = perf_matrix_filtered
            r = zeros(size(T))
            
            # Verificar se temos pelo menos uma linha válida
            valid_rows = false
            
            # Para cada problema (linha)
            for p = 1:size(T, 1)
                # Verificar se temos valores válidos para este problema
                row_values = filter(!isnan, T[p, :])
                if isempty(row_values)
                    # Pular problemas sem valores válidos
                    continue
                end
                
                valid_rows = true
                
                # Encontrar o melhor desempenho para este problema
                minval = minimum(row_values)
                
                # Calcular a razão de desempenho
                for s = 1:size(T, 2)
                    if !isnan(T[p, s])
                        r[p, s] = T[p, s] / minval
                    else
                        r[p, s] = NaN
                    end
                end
            end
            
            # Se não temos linhas válidas, pular este delta
            if !valid_rows
                println("Nenhuma linha com dados válidos encontrada para delta = $delta.")
                continue
            end
            
            # Criar os dados para o gráfico
            max_ratio = 5.0  # Limitar para melhor visualização
            ratios = range(1.0, max_ratio, length=100)
            
            # Para cada solver, plotar sua curva
            for s = 1:size(r, 2)
                solver_name = solvers_with_data[s]
                
                # Calcular a fração de problemas resolvidos dentro de cada razão
                fractions = Float64[]
                for τ in ratios
                    # Contar problemas resolvidos com razão <= τ
                    count = 0
                    total = 0
                    for p = 1:size(r, 1)
                        if !isnan(r[p, s])
                            total += 1
                            if r[p, s] <= τ
                                count += 1
                            end
                        end
                    end
                    # Evitar divisão por zero
                    push!(fractions, total > 0 ? count / total : 0.0)
                end
                
                # Plotar a curva
                lines!(ax, ratios, fractions, 
                      label=solver_name, 
                      linewidth=2)
            end
            
            # Adicionar legenda
            axislegend(ax)  # Usar o eixo explicitamente e sem posição personalizada
            
            # Salvar em formatos vetoriais
            saved_files = save_figure(fig, output_name, base_dir)
            all_saved_files[delta] = saved_files
            
        catch e
            println("✗ Error creating vector formats: $e")
        end
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
    println("Formatos disponíveis: $(join(string.(OUTPUT_FORMATS), ", "))")
    
    return all_results
end

# ========================================================================================
# FUNÇÃO PRINCIPAL
# ========================================================================================

function main()
    println("=== Gerador de Performance Profiles ===")
    println("Usando dados JLD2 do repositório AAS2025-PDFreeMO")
    println("Formatos de saída: $(join(string.(OUTPUT_FORMATS), ", "))")
    
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
            base_dir = datadir("plots", delta_str)
            println("\nDiretórios de saída para delta = $delta:")
            for fmt in OUTPUT_FORMATS
                fmt_dir = joinpath(base_dir, string(fmt))
                if isdir(fmt_dir)
                    println("  - $(uppercase(string(fmt))): $fmt_dir")
                end
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