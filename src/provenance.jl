"""
Provenance records stored next to the results in every JLD2 file.

`MOSolvers` and `MultiObjectiveProblems` are resolved by local path, so the
Manifest alone does not say which commit produced a run. Each file therefore
keeps, under `PROVENANCE_KEY/<problem>`, the git state of the path-tracked
packages and of this repository, the Julia version, the full `Project.toml` and
`Manifest.toml`, the effective solver options and the box of the problem.
"""

"""JLD2 group holding one provenance record per problem."""
const PROVENANCE_KEY = "_provenance"

"""
    git_state(dir)

Return `Dict("path", "commit", "dirty", "dirty_files")` for the git checkout at
`dir`. `dirty_files` is the `git status --porcelain` listing, untracked files
included. `commit` is `"unknown"` and `dirty` is `missing` when `dir` is not a
git checkout or `git` is unavailable.
"""
function git_state(dir::AbstractString)
    try
        commit = readchomp(`git -C $dir rev-parse HEAD`)
        dirty_files = readlines(`git -C $dir status --porcelain`)
        return Dict{String, Any}("path" => dir, "commit" => commit,
                                 "dirty" => !isempty(dirty_files), "dirty_files" => dirty_files)
    catch
        return Dict{String, Any}("path" => dir, "commit" => "unknown",
                                 "dirty" => missing, "dirty_files" => String[])
    end
end

"""
    options_record(options)

Return the fields of a `MOSolvers` options struct as a `Dict{String, Any}`, so
that the record can be read without `MOSolvers` loaded.
"""
options_record(options) = Dict{String, Any}(string(f) => getfield(options, f) for f in fieldnames(typeof(options)))

"""
    collect_provenance(configs; seed=nothing)

Build the provenance record shared by all problems in `configs`.

# Arguments
- `configs::Vector{<:ExperimentConfig}`: Configurations of the run.
- `seed`: Seed passed to `Random.seed!` by the calling script, if any.

# Returns
- `Dict{String, Any}` with `julia_version`, `git` (per repository: `MOSolvers`,
  `MultiObjectiveProblems`, `AAS2025-PDFreeMO`), `MOSolvers_names`, `project`
  and `manifest` (file contents), `solver_options` (effective options per solver
  identifier, including the PDFPM `step_tolerance_rule`), `deltas`, `nrun` and
  `seed`.
"""
function collect_provenance(configs::Vector{<:ExperimentConfig}; seed = nothing)
    solver_options = Dict{String, Any}()
    for config in configs
        name = string(config.solver_name)
        haskey(solver_options, name) && continue
        solver_options[name] = options_record(get_solver_options(config.solver_name, config.solver_config))
    end
    read_or_missing(path) = isfile(path) ? read(path, String) : missing

    return Dict{String, Any}(
        "julia_version" => string(VERSION),
        "git" => Dict{String, Any}(
            "MOSolvers" => git_state(pkgdir(MOSolvers)),
            "MultiObjectiveProblems" => git_state(pkgdir(MultiObjectiveProblems)),
            "AAS2025-PDFreeMO" => git_state(projectdir()),
        ),
        "MOSolvers_names" => string.(names(MOSolvers)),
        "project" => read_or_missing(projectdir("Project.toml")),
        "manifest" => read_or_missing(projectdir("Manifest.toml")),
        "solver_options" => solver_options,
        "deltas" => sort(unique([config.delta for config in configs])),
        "nrun" => maximum(config.run_id for config in configs),
        "seed" => seed,
    )
end

"""
    problem_box_record(problem_name)

Return the box used by the runner for `problem_name` and whether it is the
package's recommended box (`bounds === nothing`) rather than registered bounds.
"""
function problem_box_record(problem_name::Symbol)
    problem_instance = getfield(MultiObjectiveProblems, problem_name)()
    l, u = MultiObjectiveProblems.recommended_bounds(problem_instance)
    return Dict{String, Any}("box_lower" => l, "box_upper" => u,
                             "box_is_recommended" => isnothing(problem_instance.bounds))
end

"""
    write_provenance(filepath, provenance, problems)

Store `provenance`, completed with the box of each problem, under
`PROVENANCE_KEY/<problem>` in the JLD2 file at `filepath` (created if absent).

# Throws
- `error`: If the file already holds a provenance record for one of `problems`;
  results of two runs must not share a file silently.
"""
function write_provenance(filepath::String, provenance::Dict{String, Any}, problems)
    jldopen(filepath, "a+") do file
        for problem in problems
            key = "$(PROVENANCE_KEY)/$(problem)"
            haskey(file, key) && error("$filepath already holds provenance for $problem; use another file name.")
            file[key] = merge(provenance, problem_box_record(Symbol(problem)))
        end
    end
end

"""
    load_provenance(filepath, problem_name)

Return the provenance record of `problem_name` stored in `filepath`, or
`nothing` when the file has none (files written before provenance was recorded).
"""
function load_provenance(filepath::String, problem_name)
    jldopen(filepath, "r") do file
        key = "$(PROVENANCE_KEY)/$(problem_name)"
        return haskey(file, key) ? file[key] : nothing
    end
end
