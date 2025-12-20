# This script generates and saves trajectory plots (initial vs. final objective
# values) for bi-objective problems. The plots are saved as PDF in
# `data/plots/trajectories/PROBLEM_NAME/DELTA_VALUE/pdf`.
# The workflow is interactive – the user selects the JLD2 data file and the
# problem(s) to analyse.

using DrWatson
@quickactivate "AAS2025-PDFreeMO"

using JLD2
using Plots
# using CairoMakie      # (opcional) backend com suporte a PDF de alta qualidade (ver `quality = "high"`)
using MOProblems

# Load the local module to reuse utility helpers
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

"""
    quality

Controla qual biblioteca de plot será usada:

- `"normal"` (padrão): usa `Plots.jl` (mais leve para instalar) e salva em PDF.
- `"high"`: usa `CairoMakie.jl` e salva em PDF (alta qualidade).

Se você colocar `quality = "high"`, garanta que `CairoMakie` está no seu ambiente:

julia --project -e 'using Pkg; Pkg.add("CairoMakie")'

ou no REPL:
pkg> add CairoMakie
"""
const quality::String = "normal"

"""
    save_figure(plot_or_fig, name::String, base_dir::String)

Helper that saves `plot_or_fig` inside `base_dir/pdf/` with the provided `name`.
Returns a dictionary mapping the format symbol to the absolute path.
"""
function save_figure(plot_or_fig, name::String, base_dir::String)
    saved = Dict{Symbol, String}()

    fmt_dir = joinpath(base_dir, "pdf")
    mkpath(fmt_dir)
    fname = joinpath(fmt_dir, "$(name).pdf")

    try
        if plot_or_fig isa Plots.Plot
            savefig(plot_or_fig, fname)
        else
            _ensure_cairomakie_available()
            CairoMakie.save(fname, plot_or_fig)
        end
        saved[:pdf] = fname
        println("✓ Saved PDF : $fname")
    catch e
        println("✗ Failed to save PDF – $e")
    end
    return saved
end

"""
    extract_trajectory_data(filepath, problem_name, solver_name)

Return `(deltas, traj_dict)` where `traj_dict[δ]` is a vector of `(f_init, f_final)`
tuples.  Only successful runs are considered.
"""
function extract_trajectory_data(filepath::String, problem_name::Symbol, solver_name::String)
    println("\n Extracting trajectories for problem $(problem_name), solver $(solver_name)")

    # Instantiate the problem once
    problem_ctor = getfield(MOProblems, problem_name)
    problem      = problem_ctor()
    if problem.nobj != 2
        println("Skipping – not a bi-objective problem (nobj = $(problem.nobj))")
        return Float64[], Dict{Float64, Vector{Tuple{Vector{Float64}, Vector{Float64}}}}()
    end

    traj_dict = Dict{Float64, Vector{Tuple{Vector{Float64}, Vector{Float64}}}}()

    jldopen(filepath, "r") do file
        if !haskey(file, solver_name)
            println("Solver not found in file")
            return Float64[], Dict()
        end
        solver_group = file[solver_name]
        if !haskey(solver_group, string(problem_name))
            println("Problem not found for solver")
            return Float64[], Dict()
        end
        problem_group = solver_group[string(problem_name)]

        for delta_key in keys(problem_group)
            if !startswith(delta_key, "delta_")
                continue
            end
            delta_str = replace(delta_key, "delta_" => "")
            delta_val = parse(Float64, replace(delta_str, "-" => "."))
            delta_group = problem_group[delta_key]

            traj_list = Vector{Tuple{Vector{Float64}, Vector{Float64}}}()

            for run_key in keys(delta_group)
                if !startswith(run_key, "run_")
                    continue
                end
                result = delta_group[run_key]
                if !result.success
                    continue   # Ignore failed runs
                end
                push!(traj_list, (result.F_init, result.final_objective_value))
            end

            if !isempty(traj_list)
                traj_dict[delta_val] = traj_list
            end
        end
    end

    return sort(collect(keys(traj_dict))), traj_dict
end

"""
    create_and_save_trajectory_plots(filepath, problem_name, solver_name)

Generate trajectory plots for every delta available for the `(problem, solver)`
combination and save them.  Returns a dictionary `delta ⇒ saved_paths`.
"""
function create_and_save_trajectory_plots(filepath::String, problem_name::Symbol, solver_name::String)
    deltas, traj_dict = extract_trajectory_data(filepath, problem_name, solver_name)
    if isempty(deltas)
        println("No trajectories found – skipping.")
        return Dict{Float64, Dict{Symbol, String}}()
    end

    println("Quality: $(quality)")
    filename_base = replace(basename(filepath), ".jld2" => "")
    q = lowercase(quality)
    if q == "normal"
        return _create_with_plots(deltas, traj_dict, solver_name, filename_base, problem_name)
    elseif q == "high"
        _ensure_cairomakie_available()
        return _create_with_cairomakie(deltas, traj_dict, solver_name, filename_base, problem_name)
    else
        error("quality inválido: $(quality). Use \"normal\" ou \"high\".")
    end
end

function _create_with_plots(deltas, traj_dict, solver_name, filename_base, problem_name)
    gr()  # backend leve com suporte a PDF

    results = Dict{Float64, Dict{Symbol, String}}()
    for delta in deltas
        trajectories = traj_dict[delta]
        println("Number of trajectories[$(delta)] (Plots): $(length(trajectories))")

        p = plot(
            title  = "Trajectories – $(problem_name) $(solver_name)",
            xlabel = "F1(x)",
            ylabel = "F2(x)",
            legend = false,
            size   = (800, 600),
            dpi    = 600,
            fontfamily = "Computer Modern",
            framestyle = :box,
        )

        for (f_init, f_final) in trajectories
            plot!(
                p,
                [f_init[1], f_final[1]],
                [f_init[2], f_final[2]];
                color = :black,
                linewidth = 1,
                linestyle = :dash,
            )
            scatter!(p, [f_init[1]], [f_init[2]]; markersize = 8, markercolor = :gray)
            scatter!(p, [f_final[1]], [f_final[2]]; markersize = 8, markercolor = :red)
        end

        delta_str = replace(string(delta), "." => "-")
        base_dir  = datadir("plots", "trajectories", string(problem_name), delta_str)
        output_name = "trajectory_$(solver_name)_delta_$(delta_str)_$(filename_base)"
        results[delta] = save_figure(p, output_name, base_dir)
    end
    return results
end

function _create_with_cairomakie(deltas, traj_dict, solver_name, filename_base, problem_name)
    results = Dict{Float64, Dict{Symbol, String}}()
    for delta in deltas
        trajectories = traj_dict[delta]
        println("Number of trajectories[$(delta)] (CairoMakie): $(length(trajectories))")

        fig = CairoMakie.Figure(size = (800, 600))
        ax  = CairoMakie.Axis(fig[1, 1];
                   title  = "Trajectories – $(problem_name) $(solver_name)",
                   xlabel = "F₁(x)",
                   ylabel = "F₂(x)",
                   titlesize = 25,
                   xlabelsize = 25,
                   ylabelsize = 25)

        for (f_init, f_final) in trajectories
            CairoMakie.lines!(ax, [f_init[1], f_final[1]], [f_init[2], f_final[2]]; color = :black, linewidth = 1, linestyle = :dash)
            CairoMakie.scatter!(ax, [f_init[1]],  [f_init[2]];  markersize = 10, color = :gray)
            CairoMakie.scatter!(ax, [f_final[1]], [f_final[2]]; markersize = 8, color = :red)
        end

        delta_str = replace(string(delta), "." => "-")
        base_dir  = datadir("plots", "trajectories", string(problem_name), delta_str)
        output_name = "trajectory_$(solver_name)_delta_$(delta_str)_$(filename_base)"
        results[delta] = save_figure(fig, output_name, base_dir)
    end
    return results
end

"""
    create_all_trajectory_plots(filepath)

Generate trajectories for every bi-objective problem and every solver contained in
`filepath`.
"""
function create_all_trajectory_plots(filepath::String)
    println("\n=== Generating all trajectory plots ===")
    problems = AAS2025PDFreeMO.list_biobjective_problems(filepath)
    if isempty(problems)
        println("No bi-objective problems found – aborting.")
        return Dict()
    end

    all_results = Dict{Symbol, Dict{String, Any}}()
    for problem in problems
        solvers = AAS2025PDFreeMO.list_solvers_for_problem(filepath, problem)
        if isempty(solvers)
            println("No solvers found for problem $(problem)")
            continue
        end
        println("Problem $(problem) – solvers: $(join(solvers, ", "))")
        prob_res = Dict{String, Any}()
        for solver in solvers
            prob_res[solver] = create_and_save_trajectory_plots(filepath, problem, solver)
        end
        all_results[problem] = prob_res
    end
    println("\n=== Done! ===")
    return all_results
end

# ---------------------------------------------------------------------------
# Interactive entry-point
# ---------------------------------------------------------------------------
function main()
    println("=== Trajectory Plot Generator ===")
    jld2_files = list_jld2_files()
    isempty(jld2_files) && return

    # Choose file -------------------------------------------------------------
    selected_file = ""
    if length(jld2_files) == 1
        selected_file = jld2_files[1]
        println("Using file: $selected_file")
    else
        println("Choose a file to analyse:")
        for (i, f) in enumerate(jld2_files)
            println("$i. $f")
        end
        print("Enter file number: ")
        choice = parse(Int, readline())
        if 1 <= choice <= length(jld2_files)
            selected_file = jld2_files[choice]
        else
            println("Invalid choice – aborting.")
            return
        end
    end
    filepath = datadir("sims", selected_file)

    # Choose problem ---------------------------------------------------------
    problems = list_biobjective_problems(filepath)
    isempty(problems) && return

    selected_problem = nothing
    if length(problems) == 1
        selected_problem = problems[1]
        println("Using problem: $selected_problem")
    else
        println("Choose a problem to analyse:")
        for (i, p) in enumerate(problems)
            println("$i. $p")
        end
        println("$(length(problems)+1). All problems")
        print("Enter number: ")
        choice = parse(Int, readline())
        if 1 <= choice <= length(problems)
            selected_problem = problems[choice]
        elseif choice == length(problems) + 1
            create_all_trajectory_plots(filepath)
            return
        else
            println("Invalid choice – aborting.")
            return
        end
    end

    # For chosen problem, process every solver --------------------------------
    solvers = list_solvers_for_problem(filepath, selected_problem)
    if isempty(solvers)
        println("No solvers found for problem $(selected_problem)")
        return
    end

    for solver in solvers
        create_and_save_trajectory_plots(filepath, selected_problem, solver)
    end

    println("\n✔ Trajectory plots generated.")
end

# Run when executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 
