using DrWatson
@quickactivate "AAS2025-PDFreeMO"
using JLD2
using Plots
# using CairoMakie  # (opcional) backend com suporte a PDF de alta qualidade (ver `quality = "high"`)
using MOProblems

# Incluir o módulo para ter acesso às funções de análise
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# CONFIGURAÇÃO
# ========================================================================================

"""
    quality

Controla qual biblioteca de plot será usada:

- `"normal"` (padrão): usa `Plots.jl` (mais leve para instalar) e salva em `PDF`.
- `"high"`: usa `CairoMakie.jl` e salva em `PDF` (alta qualidade).

Se você colocar `quality = "high"`, garanta que `CairoMakie` está no seu ambiente:

julia --project -e 'using Pkg; Pkg.add("CairoMakie")'

ou no REPL:
pkg> add CairoMakie
"""
const quality::String = "normal"

# ========================================================================================
# FUNÇÕES AUXILIARES
# ========================================================================================

"""
    save_figure(plot_or_fig, name::String, base_dir::String)

Saves the figure/plot as PDF in a format-specific subdirectory with a name based on `name`.

# Arguments
- `plot_or_fig`: Plot/Figure to save
- `name::String`: Base name for the file
- `base_dir::String`: Base directory where format-specific subdirectories will be created

# Returns
- `Dict{Symbol,String}`: Dictionary mapping formats to saved file paths
"""
function save_figure(plot_or_fig, name::String, base_dir::String)
    saved = Dict{Symbol,String}()
    
    # Create format-specific directory
    format_dir = joinpath(base_dir, "pdf")
    mkpath(format_dir)
    
    # Create filename
    fname = joinpath(format_dir, "$(name).pdf")
    
    try
        if plot_or_fig isa Plots.Plot
            savefig(plot_or_fig, fname)
        else
            _ensure_cairomakie_available()
            CairoMakie.save(fname, plot_or_fig)
        end
        println("✓ Saved PDF: $fname")
        saved[:pdf] = fname
    catch e
        println("✗ Failed to save PDF for $name: $e")
    end
    
    return saved
end

"""
Cria e salva o plot comparativo de deltas para um problema e um solver específicos.
"""
function create_and_save_delta_plot(filepath::String, problem_name::Symbol, solver_name::String)
    println("\n=== Criando plot para: problema=$problem_name, solver=$solver_name ===")
    
    # Extrair dados do arquivo usando a função do módulo
    deltas, final_points_dict = AAS2025PDFreeMO.extract_problem_data(filepath, problem_name, solver_name)
    
    # Verificar se temos dados
    if isempty(deltas)
        println("Nenhum delta encontrado para o problema $problem_name com o solver $solver_name")
        return nothing
    end
    
    # Criar estrutura de pastas organizadas por problema
    problem_str = string(problem_name)
    base_dir = datadir("plots", "comparison", problem_str)
    filename_base = replace(basename(filepath), ".jld2" => "")
    
    q = lowercase(quality)
    if q == "normal"
        return _create_with_plots(deltas, final_points_dict, solver_name, filename_base, base_dir, problem_name)
    elseif q == "high"
        _ensure_cairomakie_available()
        return _create_with_cairomakie(deltas, final_points_dict, solver_name, filename_base, base_dir, problem_name)
    else
        error("quality inválido: $(quality). Use \"normal\" ou \"high\".")
    end
end

function _create_with_plots(deltas, final_points_dict, solver_name, filename_base, base_dir, problem_name)
    gr()  # backend leve com suporte a PDF

    # Caso 1: Apenas um delta - criar plot simples
    if length(deltas) == 1
        delta = deltas[1]
        final_points = final_points_dict[delta]

        println("Apenas um delta encontrado ($delta). Criando plot simples com Plots...")

        if isempty(final_points)
            println("Aviso: Nenhum ponto encontrado para delta = $delta")
            return nothing
        end

        f1_vals = [point[1] for point in final_points]
        f2_vals = [point[2] for point in final_points]

        p = scatter(
            f1_vals,
            f2_vals;
            title="Points for $(problem_name) ($(solver_name), δ = $delta)",
            xlabel="F1(x)",
            ylabel="F2(x)",
            markersize=8,
            markercolor=:cornflowerblue,
            label="δ = $delta",
            legend=:best,
            size=(800, 600),
            dpi=600,
            fontfamily="Computer Modern",
            framestyle=:box,
        )

        n_points = length(final_points)
        xpos = minimum(f1_vals)
        ypos = maximum(f2_vals)
        annotate!(p, xpos, ypos, text("Total points: $n_points", 10, :left))

        output_name = "single_delta_$(solver_name)_delta_$(replace(string(delta), "." => "-"))_$(filename_base)"
        return save_figure(p, output_name, base_dir)
    end

    println("Múltiplos deltas encontrados. Criando plot comparativo com Plots...")

    valid_deltas = Float64[]
    for delta in deltas
        if isempty(final_points_dict[delta])
            println("Aviso: Nenhum ponto encontrado para delta = $delta. Ignorando este delta.")
        elseif delta != 0.0
            push!(valid_deltas, delta)
        end
    end

    if isempty(valid_deltas)
        println("Nenhum delta com pontos válidos encontrado.")
        return nothing
    end

    colors = palette(:viridis, length(valid_deltas))
    p = plot(
        title="Delta Comparison - $(problem_name) ($(solver_name))",
        xlabel="F1(x)",
        ylabel="F2(x)",
        legend=:best,
        size=(800, 600),
        dpi=600,
        fontfamily="Computer Modern",
        framestyle=:box,
    )

    for (i, delta) in enumerate(valid_deltas)
        points = final_points_dict[delta]
        f1_vals = [point[1] for point in points]
        f2_vals = [point[2] for point in points]

        scatter!(
            p,
            f1_vals,
            f2_vals;
            markersize=8,
            markercolor=colors[i],
            label="δ = $delta",
        )
    end

    output_name = "delta_comparison_$(solver_name)_$(filename_base)"
    return save_figure(p, output_name, base_dir)
end

function _create_with_cairomakie(deltas, final_points_dict, solver_name, filename_base, base_dir, problem_name)
    # Caso 1: Apenas um delta - criar plot simples
    if length(deltas) == 1
        delta = deltas[1]
        final_points = final_points_dict[delta]

        println("Apenas um delta encontrado ($delta). Criando plot simples com CairoMakie...")

        if isempty(final_points)
            println("Aviso: Nenhum ponto encontrado para delta = $delta")
            return nothing
        end

        fig = CairoMakie.Figure(size=(800, 600))
        ax = CairoMakie.Axis(
            fig[1, 1];
            title="Points for $(problem_name) ($(solver_name), δ = $delta)",
            xlabel="F₁(x)",
            ylabel="F₂(x)",
        )

        f1_vals = [point[1] for point in final_points]
        f2_vals = [point[2] for point in final_points]

        CairoMakie.scatter!(
            ax,
            f1_vals,
            f2_vals;
            markersize=12,
            color=:cornflowerblue,
            label="δ = $delta",
        )

        n_points = length(final_points)
        CairoMakie.text!(ax, 0.02, 0.98; text="Total points: $n_points", align=(:left, :top), space=:relative)

        output_name = "single_delta_$(solver_name)_delta_$(replace(string(delta), "." => "-"))_$(filename_base)"
        return save_figure(fig, output_name, base_dir)
    end

    println("Múltiplos deltas encontrados. Criando plot comparativo com CairoMakie...")

    valid_deltas = Float64[]
    for delta in deltas
        if isempty(final_points_dict[delta])
            println("Aviso: Nenhum ponto encontrado para delta = $delta. Ignorando este delta.")
        elseif delta != 0.0
            push!(valid_deltas, delta)
        end
    end

    if isempty(valid_deltas)
        println("Nenhum delta com pontos válidos encontrado.")
        return nothing
    end

    fig = CairoMakie.Figure(size=(800, 600))
    ax = CairoMakie.Axis(
        fig[1, 1];
        title="Delta Comparison - $(problem_name) ($(solver_name))",
        xlabel="F₁(x)",
        ylabel="F₂(x)",
        titlesize=25,
        xlabelsize=25,
        ylabelsize=25,
    )

    colors = CairoMakie.cgrad(:viridis, length(valid_deltas), categorical=true)

    for (i, delta) in enumerate(valid_deltas)
        points = final_points_dict[delta]

        f1_vals = [point[1] for point in points]
        f2_vals = [point[2] for point in points]

        CairoMakie.scatter!(
            ax,
            f1_vals,
            f2_vals;
            markersize=12,
            color=colors[i],
            label="δ = $delta",
        )
    end

    CairoMakie.axislegend(ax)

    output_name = "delta_comparison_$(solver_name)_$(filename_base)"
    return save_figure(fig, output_name, base_dir)
end

"""
Cria plots comparativos de deltas para todos os problemas biobjetivos disponíveis
"""
function create_all_delta_comparison_plots(filepath::String)
    println("\n=== Gerando Plots Comparativos de Deltas para todos os problemas ===")
    println("Formato de saída: PDF")
    
    # Listar problemas biobjetivos disponíveis
    biobjective_problems = AAS2025PDFreeMO.list_biobjective_problems(filepath)
    
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
        available_solvers = AAS2025PDFreeMO.list_solvers_for_problem(filepath, problem)
        
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
    println("Formato disponível: PDF")
    
    return all_results
end

# ========================================================================================
# FUNÇÃO PRINCIPAL
# ========================================================================================

function main()
    println("=== Gerador de Plots Comparativos de Deltas ===")
    println("Usando dados JLD2 do repositório AAS2025-PDFreeMO")
    println("Formato de saída: PDF")
    
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
    biobjective_problems = AAS2025PDFreeMO.list_biobjective_problems(filepath)
    
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
    available_solvers = AAS2025PDFreeMO.list_solvers_for_problem(filepath, selected_problem)
    
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
    fmt_dir = joinpath(base_dir, "pdf")
    if isdir(fmt_dir)
        println("  - PDF: $fmt_dir")
    end
    
    println("\nAnálise concluída!")
end

# Executar se o script for chamado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 
