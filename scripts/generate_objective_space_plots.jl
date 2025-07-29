using DrWatson
using MOProblems
using CairoMakie     # backend com suporte a EPS, SVG, PDF
@quickactivate "AAS2025-DFreeMO"
include(srcdir("AAS2025DFreeMO.jl"))
using .AAS2025DFreeMO

# List of biobjective problems to generate plots
const PROBLEMS = [Symbol(p) for p in MOProblems.filter_problems(min_objs=2, max_objs=2)]
const GRID_POINTS = 200

println("Problems selected: $PROBLEMS")

"""
    save_figure(fig, name::Symbol, base_dir::String; formats=[:svg, :eps])

Saves the figure `fig` in specified formats (SVG, EPS, etc.) in separate subdirectories,
with a name based on `name`.

# Arguments
- `fig`: The figure to save
- `name::Symbol`: Base name for the file
- `base_dir::String`: Base directory where format-specific subdirectories will be created
- `formats`: Array of formats to save (e.g., [:svg, :eps])

# Returns
- `Dict{Symbol,String}`: Dictionary mapping formats to saved file paths
"""
function save_figure(fig, name::Symbol, base_dir::String; formats=[:svg, :eps])
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
    generate_objective_space_plot(problem_name::Symbol;
                                 grid_points::Int=100,
                                 formats=[:svg, :eps])

Creates and saves the objective space plot for a biobjective problem.
Returns the Figure object from Makie.

# Arguments
- `problem_name::Symbol`: Problem name
- `grid_points::Int=100`: Number of grid points
- `formats`: Array of output formats (e.g., [:svg, :eps])

# Returns
- `Tuple{Figure, Dict}`: Makie Figure object and dictionary of saved files
"""
function generate_objective_space_plot(problem_name::Symbol;
                                      grid_points::Int=100,
                                      formats=[:svg, :eps])
    println("\n=== Generating plot for $problem_name ===")
    
    # Create problem instance
    problem = create_problem_instance(problem_name)
    println("Problem: $(problem.name), objectives: $(problem.nobj)")
    
    if problem.nobj != 2
        error("Only biobjective problems are supported.")
    end
    
    # Get the objective space data using the existing function in utils.jl
    f1_vals, f2_vals = extract_objective_space_data(problem, grid_points=grid_points)
    
    # Create Makie figure
    fig = Figure(size=(800, 600))
    ax = Axis(fig[1,1], 
              title="Objective Space for $(problem.name)",
              xlabel="F₁(x)",
              ylabel="F₂(x)")
    
    # Plot the points
    scatter!(ax, f1_vals, f2_vals, 
             markersize=2, 
             color=(:cornflowerblue, 0.3),
             label="Objective Space")
    
    # Save the figure in format-specific directories
    base_dir = datadir("plots", "obj_space")
    saved = save_figure(fig, problem_name, base_dir; formats=formats)
    
    return fig, saved
end

"""
    create_problem_instance(problem_name::Symbol)

Creates a problem instance from the name.
"""
function create_problem_instance(problem_name::Symbol)
    try
        problem_func = getfield(MOProblems, problem_name)
        return problem_func()
    catch e
        error("Could not create problem instance $problem_name: $e")
    end
end

function main()
    println("Starting generation of objective space plots...")
    println("Total: $(length(PROBLEMS)), points: $GRID_POINTS")
    
    # Show output directories
    base_dir = datadir("plots", "obj_space")
    println("Output directories:")
    for fmt in [:svg, :eps]
        println("  - $(uppercase(string(fmt))): $(joinpath(base_dir, string(fmt)))")
    end
    
    successful, failed = 0, 0
    all_saved = Dict{Symbol,Dict}()
    
    for (i, pname) in enumerate(PROBLEMS)
        println("\n[$i/$(length(PROBLEMS))] Processing $pname")
        try
            fig, saved = generate_objective_space_plot(pname;
                            grid_points=GRID_POINTS, formats=[:svg, :eps])
            all_saved[pname] = saved
            successful += 1
        catch e
            println("Error processing $pname: $e")
            failed += 1
        end
    end
    
    println("\n" * "="^60)
    println("SUMMARY: processed=$(length(PROBLEMS)), successful=$successful, failed=$failed")
    println("Output directories:")
    for fmt in [:svg, :eps]
        println("  - $(uppercase(string(fmt))): $(joinpath(base_dir, string(fmt)))")
    end
    println("="^60)
    
    return all_saved
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end