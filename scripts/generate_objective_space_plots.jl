using DrWatson
using MOProblems
using Plots
# using CairoMakie     # (opcional) backend com suporte a PDF de alta qualidade (ver `quality = "high"`)
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ==============================================================================
# Configuração
# ==============================================================================
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

# List of biobjective problems to generate plots
const PROBLEMS = [Symbol(p) for p in MOProblems.filter_problems(min_objs=2, max_objs=2)]
# const PROBLEMS = [Symbol("AAS1")]
const GRID_POINTS = 200

println("Problems selected: $PROBLEMS")

"""
    save_figure(plot_or_fig, name::Symbol, base_dir::String)

Saves the figure/plot as PDF in `base_dir/pdf`, with a name based on `name`.

# Arguments
- `plot_or_fig`: Plot/Figure to save
- `name::Symbol`: Base name for the file
- `base_dir::String`: Base directory where the `pdf` subdirectory will be created

# Returns
- `String`: Saved file path
"""
function save_figure(plot_or_fig, name::Symbol, base_dir::String)
    format_dir = joinpath(base_dir, "pdf")
    mkpath(format_dir)

    fname = joinpath(format_dir, "$(name).pdf")

    if plot_or_fig isa Plots.Plot
        savefig(plot_or_fig, fname)
    else
        # CairoMakie/Makie path (loaded only when `quality == "high"`)
        CairoMakie.save(fname, plot_or_fig)
    end

    println("✓ Saved pdf: $fname")
    return fname
end

"""
    generate_objective_space_plot(problem_name::Symbol;
                                 grid_points::Int=100)

Creates and saves the objective space plot for a biobjective problem.
Retorna o objeto de plot (Plots.jl) ou Figure (Makie), dependendo de `quality`.

# Arguments
- `problem_name::Symbol`: Problem name
- `grid_points::Int=100`: Number of grid points

# Returns
- `Tuple{Any, String}`: Plot/Figure e caminho do PDF salvo
"""
function generate_objective_space_plot(problem_name::Symbol;
                                      grid_points::Int=100)
    println("\n=== Generating plot for $problem_name ===")

    # Create problem instance
    problem = try
        problem_func = getfield(MOProblems, problem_name)
        problem_func()
    catch e
        error("Could not create problem instance $problem_name: $e")
    end
    println("Problem: $(problem.name), objectives: $(problem.nobj)")
    
    if problem.nobj != 2
        error("Only biobjective problems are supported.")
    end
    
    # Get the objective space data using the existing function in utils.jl
    f1_vals, f2_vals = extract_objective_space_data(problem, grid_points=grid_points)

    if lowercase(quality) == "normal"
        # Use GR backend for speed and decent PDF support
        gr()

        p = scatter(
            f1_vals,
            f2_vals;
            title="Objective Space for $(problem.name)",
            xlabel="F1(x)",
            ylabel="F2(x)",
            label="Objective Space",
            markersize=4,
            markercolor=:cornflowerblue,
            markeralpha=0.05,
            markerstrokewidth=0,
            size=(800, 600),
            dpi=600,
            plot_titlefontsize=16,
            guidefontsize=14,
            tickfontsize=10,
            fontfamily="Computer Modern",
            legend=:best,
            framestyle=:box,
        )

        base_dir = datadir("plots", "obj_space")
        saved_pdf = save_figure(p, problem_name, base_dir)
        return p, saved_pdf
    elseif lowercase(quality) == "high"
        _ensure_cairomakie_available()

        fig = CairoMakie.Figure(size=(800, 600))
        ax = CairoMakie.Axis(
            fig[1, 1];
            title="Objective Space for $(problem.name)",
            xlabel="F₁(x)",
            ylabel="F₂(x)",
            titlesize=25,
            xlabelsize=25,
            ylabelsize=25,
        )

        CairoMakie.scatter!(
            ax,
            f1_vals,
            f2_vals;
            markersize=4,
            color=(:cornflowerblue, 0.3),
            label="Objective Space",
        )

        base_dir = datadir("plots", "obj_space")
        saved_pdf = save_figure(fig, problem_name, base_dir)
        return fig, saved_pdf
    else
        error("quality inválido: $(quality). Use \"normal\" ou \"high\".")
    end
end

function _ensure_cairomakie_available()
    try
        @eval using CairoMakie
    catch e
        error(
            "quality = \"high\" requer CairoMakie no ambiente.\n" *
            "Instale com:\n" *
            "  julia --project -e 'using Pkg; Pkg.add(\"CairoMakie\")'\n\n" *
            "Erro original: $(e)",
        )
    end
    return nothing
end

function main()
    println("Starting generation of objective space plots (quality=$quality)...")
    println("Total: $(length(PROBLEMS)), points: $GRID_POINTS")

    # Show output directories
    base_dir = datadir("plots", "obj_space")
    pdf_dir = joinpath(base_dir, "pdf")
    println("Output directory:")
    println("  - PDF: $pdf_dir")

    successful, failed = 0, 0
    all_saved = Dict{Symbol,String}()

    for (i, pname) in enumerate(PROBLEMS)
        println("\n[$i/$(length(PROBLEMS))] Processing $pname")
        try
            fig, saved = generate_objective_space_plot(pname;
                            grid_points=GRID_POINTS)
            all_saved[pname] = saved
            successful += 1
        catch e
            println("Error processing $pname: $e")
            failed += 1
        end
    end

    println("\n" * "="^60)
    println("SUMMARY: processed=$(length(PROBLEMS)), successful=$successful, failed=$failed")
    println("Output directory:")
    println("  - PDF: $pdf_dir")
    println("="^60)

    return all_saved
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
