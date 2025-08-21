using DrWatson
@quickactivate "AAS2025-DFreeMO"
using JLD2
using CairoMakie  # Usando apenas CairoMakie para formatos vetoriais
using MOProblems

# Incluir o módulo para ter acesso às funções de análise
include(srcdir("AAS2025DFreeMO.jl"))
using .AAS2025DFreeMO

# ========================================================================================
# CONFIGURAÇÃO
# ========================================================================================

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

# Função list_jld2_files agora importada do módulo AAS2025DFreeMO

# Função extract_problem_data agora importada do módulo AAS2025DFreeMO

# Funções is_biobjective_problem e list_biobjective_problems agora importadas do módulo AAS2025DFreeMO

"""
Cria e salva o plot comparativo de deltas para um problema e um solver específicos.
"""
function create_and_save_delta_plot(filepath::String, problem_name::Symbol, solver_name::String)
    println("\n=== Criando plot para: problema=$problem_name, solver=$solver_name ===")
    
    # Extrair dados do arquivo usando a função do módulo
    deltas, final_points_dict = AAS2025DFreeMO.extract_problem_data(filepath, problem_name, solver_name)
    
    # Verificar se temos dados
    if isempty(deltas)
        println("Nenhum delta encontrado para o problema $problem_name com o solver $solver_name")
        return nothing
    end
    
    # Criar estrutura de pastas organizadas por problema
    problem_str = string(problem_name)
    base_dir = datadir("plots", "comparison", problem_str)
    filename_base = replace(basename(filepath), ".jld2" => "")
    
    # Caso 1: Apenas um delta - criar plot simples
    if length(deltas) == 1
        delta = deltas[1]
        final_points = final_points_dict[delta]
        
        println("Apenas um delta encontrado ($delta). Criando plot simples...")
        
        # Verificar se temos pontos para este delta
        if isempty(final_points)
            println("Aviso: Nenhum ponto encontrado para delta = $delta")
            return nothing
        end
        
        # Criar e salvar com CairoMakie
        try
            # Criar o gráfico com CairoMakie
            fig = Figure(size=(800, 600))
            ax = Axis(fig[1, 1], 
                     title="Points for $(problem_name) ($(solver_name), δ = $delta)",
                     xlabel="F₁(x)",
                     ylabel="F₂(x)")
            
            # Extrair coordenadas
            f1_vals = [point[1] for point in final_points]
            f2_vals = [point[2] for point in final_points]
            
            # Plotar os pontos
            scatter!(ax, f1_vals, f2_vals, 
                    markersize=12, 
                    color=:cornflowerblue,
                    label="δ = $delta")
            
            # Adicionar estatísticas
            n_points = length(final_points)
            text!(ax, 0.02, 0.98, text="Total points: $n_points", 
                 align=(:left, :top), space=:relative)
            
            # Salvar em formatos vetoriais
            output_name = "single_delta_$(solver_name)_delta_$(replace(string(delta), "." => "-"))_$(filename_base)"
            saved_files = save_figure(fig, output_name, base_dir)
            
            return saved_files
        catch e
            println("✗ Error creating vector formats: $e")
            return nothing
        end
    end
    
    # Caso 2: Múltiplos deltas - criar plot comparativo
    println("Múltiplos deltas encontrados. Criando plot comparativo...")
    
    # Verificar se temos pontos para cada delta e remover deltas sem pontos
    valid_deltas = Float64[]
    for delta in deltas
        if isempty(final_points_dict[delta])
            println("Aviso: Nenhum ponto encontrado para delta = $delta. Ignorando este delta.")
        elseif delta != 0.0
            push!(valid_deltas, delta)
        end
    end
    
    # Verificar se ainda temos deltas válidos após a filtragem
    if isempty(valid_deltas)
        println("Nenhum delta com pontos válidos encontrado.")
        return nothing
    end
    
    # Criar e salvar com CairoMakie
    try
        # Criar o gráfico com CairoMakie
        fig = Figure(size=(800, 600))
        ax = Axis(fig[1, 1], 
                 title="Delta Comparison - $(problem_name) (DFPM)",
                 xlabel="F₁(x)",
                 ylabel="F₂(x)",
                 titlesize = 25,
                 xlabelsize = 25,
                 ylabelsize = 25)
        
        # Cores distintas para cada delta
        colors = cgrad(:viridis, length(valid_deltas), categorical=true)
        
        # Para cada delta válido, plotar os pontos
        for (i, delta) in enumerate(valid_deltas)
            points = final_points_dict[delta]
            
            # Extrair coordenadas
            f1_vals = [point[1] for point in points]
            f2_vals = [point[2] for point in points]
            
            # Plotar os pontos
            scatter!(ax, f1_vals, f2_vals, 
                    markersize=12, 
                    color=colors[i],
                    label="δ = $delta")
        end
        
        # Adicionar legenda
        axislegend(ax)  # Usar o eixo explicitamente e sem posição personalizada
        
        # Salvar em formatos vetoriais
        output_name = "delta_comparison_$(solver_name)_$(filename_base)"
        saved_files = save_figure(fig, output_name, base_dir)
        
        return saved_files
    catch e
        println("✗ Error creating vector formats: $e")
        return nothing
    end
end

"""
Cria plots comparativos de deltas para todos os problemas biobjetivos disponíveis
"""
function create_all_delta_comparison_plots(filepath::String)
    println("\n=== Gerando Plots Comparativos de Deltas para todos os problemas ===")
    println("Formatos de saída: $(join(string.(OUTPUT_FORMATS), ", "))")
    
    # Listar problemas biobjetivos disponíveis
    biobjective_problems = AAS2025DFreeMO.list_biobjective_problems(filepath)
    
    if isempty(biobjective_problems)
        println("Nenhum problema biobjetivo encontrado para análise.")
        return
    end
    
    println("Problemas encontrados: $biobjective_problems")
    
    all_results = Dict{Symbol, Dict{String, Any}}()
    
    # Para cada problema, criar plots para todos os solvers disponíveis
    for problem in biobjective_problems
        println("\n--- Processando problema: $problem ---")
        
        # Listar solvers para o problema selecionado
        available_solvers = AAS2025DFreeMO.list_solvers_for_problem(filepath, problem)
        
        if isempty(available_solvers)
            println("Nenhum solver encontrado para o problema '$problem'.")
            continue
        end
        
        println("Solvers encontrados para '$problem': $(join(available_solvers, ", "))")
        
        problem_results = Dict{String, Any}()
        
        # Criar um plot para cada solver
        for solver in available_solvers
            saved_files = create_and_save_delta_plot(filepath, problem, solver)
            problem_results[solver] = saved_files
        end
        
        all_results[problem] = problem_results
    end
    
    println("\n=== Todos os Plots Comparativos de Deltas foram gerados ===")
    println("Formatos disponíveis: $(join(string.(OUTPUT_FORMATS), ", "))")
    
    return all_results
end

# ========================================================================================
# FUNÇÃO PRINCIPAL
# ========================================================================================

function main()
    println("=== Gerador de Plots Comparativos de Deltas ===")
    println("Usando dados JLD2 do repositório AAS2025-DFreeMO")
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
    
    # Obter caminho completo do arquivo
    filepath = datadir("sims", selected_file)
    
    # Listar problemas biobjetivos disponíveis
    biobjective_problems = AAS2025DFreeMO.list_biobjective_problems(filepath)
    
    if isempty(biobjective_problems)
        println("Nenhum problema biobjetivo encontrado para análise.")
        return
    end
    
    # Escolher problema
    if length(biobjective_problems) == 1
        selected_problem = biobjective_problems[1]
        println("\nUsando problema: $selected_problem")
    else
        println("\nEscolha um problema para analisar:")
        for (i, problem) in enumerate(biobjective_problems)
            println("$i. $problem")
        end
        println("$(length(biobjective_problems) + 1). Todos os problemas")
        
        print("Digite o número do problema: ")
        problem_choice = parse(Int, readline())
        
        if 1 <= problem_choice <= length(biobjective_problems)
            selected_problem = biobjective_problems[problem_choice]
        elseif problem_choice == length(biobjective_problems) + 1
            # Criar plots para todos os problemas
            create_all_delta_comparison_plots(filepath)
            println("\nAnálise concluída!")
            return
        else
            println("Escolha inválida.")
            return
        end
    end
    
    # Listar solvers para o problema selecionado
    available_solvers = AAS2025DFreeMO.list_solvers_for_problem(filepath, selected_problem)
    
    if isempty(available_solvers)
        println("Nenhum solver encontrado para o problema '$selected_problem'.")
        return
    end
    
    println("\nSolvers encontrados para '$selected_problem': $(join(available_solvers, ", "))")
    
    # Criar um plot para cada solver
    for solver in available_solvers
        create_and_save_delta_plot(filepath, selected_problem, solver)
    end
    
    # Mostrar diretórios de saída
    base_dir = datadir("plots", "comparison", string(selected_problem))
    println("\nDiretórios de saída:")
    for fmt in OUTPUT_FORMATS
        fmt_dir = joinpath(base_dir, string(fmt))
        if isdir(fmt_dir)
            println("  - $(uppercase(string(fmt))): $fmt_dir")
        end
    end
    
    println("\nAnálise concluída!")
end

# Executar se o script for chamado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 