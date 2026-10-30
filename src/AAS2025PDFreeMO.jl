"""
Tools for configuring, running, and analyzing multiobjective experiments. The module wires together solver options, experiment orchestration, post-processing, and plotting helpers.
"""
module AAS2025PDFreeMO

using DrWatson
using Random
using JLD2
using LinearAlgebra: BLAS  # stdlib already loaded by MOSolvers; BLAS configuration for the provenance
using MOSolvers
using MultiObjectiveProblems

include("solver_options.jl")
include("types.jl")
include("utils.jl")
include("provenance.jl")
include("experiment_runner.jl")
include("data_analysis.jl")
include("merit.jl")

export ExperimentResult, ExperimentConfig
export datas
export CommonSolverOptions, SolverSpecificOptions, SolverConfiguration, get_solver_options
export generate_experiment_configs, run_experiment, run_experiment_with_batch_saving, warm_up
export collect_provenance, write_provenance, load_provenance, machine_record, part_name

# Data analysis helpers
export list_jld2_files
export is_biobjective_problem, list_biobjective_problems, filter_solvers
export extract_performance_data, extract_problem_data
export list_solvers_for_problem, run_converged

# Stationarity merit of returned points
export MERIT_TOLS, merit_params, merit_objective, merit_w1, merit_w1_dual
export _ensure_cairomakie_available

# Plotting helpers
export extract_objective_space_data

end # module AAS2025PDFreeMO
