"""
Tools for configuring, running, and analyzing multiobjective experiments. The module wires together solver options, experiment orchestration, post-processing, and plotting helpers.
"""
module AAS2025PDFreeMO

using DrWatson
using Random
using JLD2
using MOSolvers
using MultiObjectiveProblems

include("solver_options.jl")
include("types.jl")
include("utils.jl")
include("provenance.jl")
include("experiment_runner.jl")
include("data_analysis.jl")

export ExperimentResult, ExperimentConfig
export datas
export CommonSolverOptions, SolverSpecificOptions, SolverConfiguration, get_solver_options
export generate_experiment_configs, run_experiment, run_experiment_with_batch_saving
export collect_provenance, write_provenance, load_provenance

# Data analysis helpers
export list_jld2_files
export is_biobjective_problem, list_biobjective_problems, filter_solvers
export extract_performance_data, extract_problem_data
export list_solvers_for_problem, run_converged
export _ensure_cairomakie_available

# Plotting helpers
export extract_objective_space_data

end # module AAS2025PDFreeMO
