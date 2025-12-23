using DrWatson
@quickactivate "AAS2025-PDFreeMO"
using JLD2
using Plots
# using CairoMakie  # (optional) high-quality PDF backend (see `quality = "high"`)
using MOProblems

# Load the local module for analysis utilities
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# CONFIGURATION
# ========================================================================================

"""
    quality

Controls which plotting backend to use:

- `"normal"` (default): uses `Plots.jl` (lighter dependency footprint) and saves PDF.
- `"high"`: uses `CairoMakie.jl` and saves PDF (higher quality).

If you choose `quality = "high"`, ensure `CairoMakie` is available in your environment:

julia --project -e 'using Pkg; Pkg.add("CairoMakie")'
"""
const quality::String = "normal"

# ========================================================================================
# HELPER FUNCTIONS
# ========================================================================================

"""
    save_figure(plot_or_fig, name::String, base_dir::String)

Save the figure/plot as PDF under a format-specific subdirectory with a name based
on `name`.

# Arguments
- `plot_or_fig`: Plot or figure to save.
- `name::String`: Base name for the file.
- `base_dir::String`: Base directory where format-specific subdirectories are created.

# Returns
- `Dict{Symbol,String}`: Dictionary mapping formats to saved file paths.
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
Create and save the delta-comparison plot for a specific problem and solver.
"""
function create_and_save_delta_plot(filepath::String, problem_name::Symbol, solver_name::String)
    println("\n=== Creating plot for: problem=$problem_name, solver=$solver_name ===")
    
    # Extract data from file using module helper
    deltas, final_points_dict = AAS2025PDFreeMO.extract_problem_data(filepath, problem_name, solver_name)
    
    if isempty(deltas)
        println("No deltas found for problem $problem_name with solver $solver_name")
        return nothing
    end
    
    # Organize output directories by problem
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
        error("Invalid quality setting: $(quality). Use \"normal\" or \"high\".")
    end
end

function _create_with_plots(deltas, final_points_dict, solver_name, filename_base, base_dir, problem_name)
    gr()  # lightweight backend with PDF support

    # Case 1: single delta – simple plot
    if length(deltas) == 1
        delta = deltas[1]
        final_points = final_points_dict[delta]

        println("Single delta found ($delta). Creating simple plot with Plots...")

        if isempty(final_points)
            println("Warning: No points found for delta = $delta")
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

    println("Multiple deltas found. Creating comparative plot with Plots...")

    valid_deltas = Float64[]
    for delta in deltas
        if isempty(final_points_dict[delta])
            println("Warning: No points found for delta = $delta. Skipping this delta.")
        elseif delta != 0.0
            push!(valid_deltas, delta)
        end
    end

    if isempty(valid_deltas)
        println("No deltas with valid points found.")
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
    # Case 1: single delta – simple plot
    if length(deltas) == 1
        delta = deltas[1]
        final_points = final_points_dict[delta]

        println("Single delta found ($delta). Creating simple plot with CairoMakie...")

        if isempty(final_points)
            println("Warning: No points found for delta = $delta")
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

    println("Multiple deltas found. Creating comparative plot with CairoMakie...")

    valid_deltas = Float64[]
    for delta in deltas
        if isempty(final_points_dict[delta])
            println("Warning: No points found for delta = $delta. Skipping this delta.")
        elseif delta != 0.0
            push!(valid_deltas, delta)
        end
    end

    if isempty(valid_deltas)
        println("No deltas with valid points found.")
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
Create delta-comparison plots for all available bi-objective problems.
"""
function create_all_delta_comparison_plots(filepath::String)
    println("\n=== Generating delta-comparison plots for all problems ===")
    println("Output format: PDF")
    
    # List available bi-objective problems
    biobjective_problems = AAS2025PDFreeMO.list_biobjective_problems(filepath)
    
    if isempty(biobjective_problems)
        println("No bi-objective problems found for analysis.")
        return
    end
    
    println("Problems found: $biobjective_problems")
    
    all_results = Dict{Symbol, Dict{String, Any}}()
    
    # For each problem, create plots for every available solver
    for problem in biobjective_problems
        println("\n--- Processing problem: $problem ---")
        
        # List solvers for the selected problem
        available_solvers = AAS2025PDFreeMO.list_solvers_for_problem(filepath, problem)
        
        if isempty(available_solvers)
            println("No solvers found for problem '$problem'.")
            continue
        end
        
        println("Solvers found for '$problem': $(join(available_solvers, ", "))")
        
        problem_results = Dict{String, Any}()
        
        # Create one plot per solver
        for solver in available_solvers
            saved_files = create_and_save_delta_plot(filepath, problem, solver)
            problem_results[solver] = saved_files
        end
        
        all_results[problem] = problem_results
    end
    
    println("\n=== All delta-comparison plots generated ===")
    println("Available format: PDF")
    
    return all_results
end

# ========================================================================================
# MAIN FUNCTION
# ========================================================================================

"""
Interactive CLI that selects a JLD2 file, chooses bi-objective problems and solvers,
and generates delta-comparison plots in PDF format.
"""
function main()
    println("=== Delta Comparison Plot Generator ===")
    println("Using JLD2 data from the AAS2025-PDFreeMO repository")
    println("Output format: PDF")
    
    # List available files
    jld2_files = list_jld2_files()
    
    if isempty(jld2_files)
        return
    end
    
    # Choose file
    if length(jld2_files) == 1
        selected_file = jld2_files[1]
        println("\nUsing file: $selected_file")
    else
        println("\nChoose a file to analyze:")
        for (i, file) in enumerate(jld2_files)
            println("$i. $file")
        end
        
        print("Enter file number: ")
        choice = parse(Int, readline())
        
        if 1 <= choice <= length(jld2_files)
            selected_file = jld2_files[choice]
        else
            println("Invalid choice.")
            return
        end
    end
    
    # Build full path to file
    filepath = datadir("sims", selected_file)
    
    # List available bi-objective problems
    biobjective_problems = AAS2025PDFreeMO.list_biobjective_problems(filepath)
    
    if isempty(biobjective_problems)
        println("No bi-objective problems found for analysis.")
        return
    end
    
    # Choose problem
    if length(biobjective_problems) == 1
        selected_problem = biobjective_problems[1]
        println("\nUsing problem: $selected_problem")
    else
        println("\nChoose a problem to analyze:")
        for (i, problem) in enumerate(biobjective_problems)
            println("$i. $problem")
        end
        println("$(length(biobjective_problems) + 1). All problems")
        
        print("Enter problem number: ")
        problem_choice = parse(Int, readline())
        
        if 1 <= problem_choice <= length(biobjective_problems)
            selected_problem = biobjective_problems[problem_choice]
        elseif problem_choice == length(biobjective_problems) + 1
            # Create plots for all problems
            create_all_delta_comparison_plots(filepath)
            println("\nAnalysis complete!")
            return
        else
            println("Invalid choice.")
            return
        end
    end
    
    # List solvers for the selected problem
    available_solvers = AAS2025PDFreeMO.list_solvers_for_problem(filepath, selected_problem)
    
    if isempty(available_solvers)
        println("No solvers found for problem '$selected_problem'.")
        return
    end
    
    println("\nSolvers found for '$selected_problem': $(join(available_solvers, ", "))")
    
    # Create one plot per solver
    for solver in available_solvers
        create_and_save_delta_plot(filepath, selected_problem, solver)
    end
    
    # Show output directories
    base_dir = datadir("plots", "comparison", string(selected_problem))
    println("\nOutput directories:")
    fmt_dir = joinpath(base_dir, "pdf")
    if isdir(fmt_dir)
        println("  - PDF: $fmt_dir")
    end
    
    println("\nAnalysis complete!")
end

# Execute when run directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 
