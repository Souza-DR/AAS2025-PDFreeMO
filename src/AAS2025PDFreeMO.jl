module AAS2025PDFreeMO

    using DrWatson
    using Random
    using JLD2
    using MOSolvers
    using MOProblems
    using MOMetrics

    include("solver_options.jl")
    include("types.jl")
    include("utils.jl")
    include("experiment_runner.jl")
    include("data_analysis.jl")

    export ExperimentResult, ExperimentConfig
    export datas, safe_evalf_solver, safe_evalJf_solver
    export CommonSolverOptions, SolverSpecificOptions, SolverConfiguration, get_solver_options
    export generate_experiment_configs, run_experiment, run_experiment_with_batch_saving
    
    # Funções de análise de dados
    export list_jld2_files, get_file_metadata
    export is_biobjective_problem, list_biobjective_problems, filter_solvers
    export extract_performance_data, extract_problem_data
    export get_successful_results_count, validate_biobjective_data
    export list_solvers_for_problem
    
    # Funções de plotagem
    export create_delta_comparison_plot, create_single_delta_plot, save_single_delta_plot
    export extract_objective_space_data, plot_trajectories

end # module AAS2025PDFreeMO 