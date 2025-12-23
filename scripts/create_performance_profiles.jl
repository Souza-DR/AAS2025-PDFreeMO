using DrWatson
@quickactivate "AAS2025-PDFreeMO"
using JLD2
using BenchmarkProfiles
using Statistics
using Printf
using Plots
using PlotThemes

# Load the module to access analysis types and functions
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

# ========================================================================================
# CONFIGURATION
# ========================================================================================

# Solver names (must match the names saved in JLD2)
const SOLVER_NAMES = ["PDFPM", "CondG", "ProxGrad"]

# Metrics available for analysis
const METRICS = Dict(
    "iter" => "Iterations",
    "n_f_evals" => "Function evaluations",
    "n_Jf_evals" => "Gradient evaluations",
    "total_time" => "Execution time (s)"
)

# ========================================================================================
# HELPER FUNCTIONS
# ========================================================================================

"""
Create and save the performance profile.
"""
function create_performance_profile(filepath::String, metric::String)
    perf_matrix, instance_info = AAS2025PDFreeMO.extract_performance_data(filepath, metric, SOLVER_NAMES)
    
    if perf_matrix === nothing || isempty(perf_matrix)
        println("Could not extract performance data.")
        return Dict{Float64, Dict{Symbol, String}}()
    end

    # Filter problems that none of the solvers solved
    valid_rows = []
    # valid_rows = findall(row -> !all(isnan, row) , eachrow(perf_matrix))
    valid_rows = findall(row -> !all(isnan, row) && !any(==(0.0), row), eachrow(perf_matrix))


    println("Total instances: $(size(perf_matrix, 1)), Valid: $(length(valid_rows))")
    
    # Create a PP for all deltas simultaneously
    # Prepare filename
    filename_base = replace(basename(filepath), ".jld2" => "")
    output_name = "pp_$(metric)_$(filename_base)"
    title_text = "$(METRICS[metric])"

    # Create the plot
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
    println("Performance profile saved at: $output_file")
    # Find unique deltas from the instance information
    unique_deltas = unique([info[2] for info in instance_info])
    println("\nDeltas found: $unique_deltas. Generating one profile per delta.")
    
    all_saved_files = Dict{Float64, Dict{Symbol, String}}()
    
    # Iterate over each delta and create a performance profile
    for delta in unique_deltas
        println("\n--- Processing Delta = $delta ---")
        
        # Filter the performance matrix and instance info for the current delta
        indices = findall(info -> info[2] == delta, instance_info)
        
        if isempty(indices)
            println("No instances found for delta $delta.")
            continue
        end
        
        perf_matrix_for_delta = perf_matrix[indices, :]
        # valid_rows = findall(row -> !all(isnan, row) , eachrow(perf_matrix_for_delta))
        valid_rows = findall(row -> !all(isnan, row) && !any(==(0.0), row), eachrow(perf_matrix_for_delta))

        perf_matrix_for_delta = perf_matrix_for_delta[valid_rows, :]

        # Check whether we have valid data for this delta
        if all(isnan, perf_matrix_for_delta)
            println("No valid data found for metric '$metric' with delta = $delta.")
            continue
        end
        
        # Filter solvers that have data for this delta
        solvers_with_data = String[]
        valid_cols = []
        for (solver_idx, solver) in enumerate(SOLVER_NAMES)
            if solver_idx <= size(perf_matrix_for_delta, 2) && !all(isnan, perf_matrix_for_delta[:, solver_idx])
                push!(solvers_with_data, String(solver))
                push!(valid_cols, solver_idx)
            end
        end
        
        if length(solvers_with_data) < 2
            println("At least two solvers with valid data are required to create the profile for delta = $delta.")
            continue
        end
        
        perf_matrix_filtered = perf_matrix_for_delta[:, valid_cols]
        
        # Create folder structure organized by delta
        delta_str_folder = replace(string(delta), "." => "-")
        base_dir = datadir("plots", "PP", delta_str_folder)
        
        # Prepare filename
        filename_base = replace(basename(filepath), ".jld2" => "")
        output_name = "pp_$(metric)_$(filename_base)"

        title_text = "$(METRICS[metric]) (δ = $delta)"
    
        # # Create the plot
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
        println("Performance profile saved at: $output_file")
    end
    
    return all_saved_files
end

"""
Create performance profiles for all available metrics.
"""
function create_all_performance_profiles(filepath::String)
    println("\n=== Generating Performance Profiles for all metrics ===")
    
    all_results = Dict{String, Any}()
    
    for (metric, description) in METRICS
        println("\n--- Processing metric: $metric ($description) ---")
        results = create_performance_profile(filepath, metric)
        all_results[metric] = results
    end
    
    println("\n=== All Performance Profiles generated ===")
    
    return all_results
end

# ========================================================================================
# MAIN FUNCTION
# ========================================================================================

function main()
    println("=== Performance Profile Generator ===")
    println("Using JLD2 data from the AAS2025-PDFreeMO repository")
    
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
    
    # Choose metric
    println("\nChoose the metric for the performance profile:")
    for (i, (metric, description)) in enumerate(METRICS)
        println("$i. $metric ($description)")
    end
    println("$(length(METRICS) + 1). All metrics")
    
    print("Enter metric number: ")
    metric_choice = parse(Int, readline())
    
    metrics_list = collect(keys(METRICS))
    if 1 <= metric_choice <= length(metrics_list)
        selected_metric = metrics_list[metric_choice]
        # Create the performance profile for a specific metric
        filepath = datadir("sims", selected_file)
        results = create_performance_profile(filepath, selected_metric)
        
        # Show output directories
        for delta in keys(results)
            delta_str = replace(string(delta), "." => "-")
            base_dir = datadir("plots", "PP", delta_str, "pdf")
            println("\nOutput directory for delta = $delta:")
            if isdir(base_dir)
                println("  - PDF: $base_dir")
            end
        end
        
    elseif metric_choice == length(metrics_list) + 1
        # Create performance profiles for all metrics
        filepath = datadir("sims", selected_file)
        create_all_performance_profiles(filepath)
    else
        println("Invalid choice.")
        return
    end
    
    println("\nAnalysis complete!")
end

# Run when the script is called directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end 