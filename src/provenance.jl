"""
Provenance records stored next to the results in every JLD2 file.

`MOSolvers` and `MultiObjectiveProblems` are resolved by local path, so the
Manifest alone does not say which commit produced a run. Each file therefore
keeps, under `PROVENANCE_KEY/<problem>`, the git state of the path-tracked
packages and of this repository, the Julia version, the full `Project.toml` and
`Manifest.toml`, the machine, the effective solver options and the box of the
problem. A problem whose deltas are solved in separate parts (partitioned runs)
has one record per part, under `PROVENANCE_KEY/<part>` (see `part_name`).
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
    machine_record()

Return the machine the process runs on: host name, CPU model and target, number
of logical CPUs, total memory, BLAS configuration and threads, Julia threads, the
`JULIA_NUM_THREADS`, `OPENBLAS_NUM_THREADS` and `OMP_NUM_THREADS` variables
(`missing` when unset) and the CPU affinity (`Cpus_allowed_list` of
`/proc/self/status`; `missing` outside Linux). Results depend on the CPU, so the
record says where they were produced. Draws nothing from the global random stream.
"""
function machine_record()
    cpu = Sys.cpu_info()
    affinity = missing
    if Sys.islinux() && isfile("/proc/self/status")
        for line in eachline("/proc/self/status")
            startswith(line, "Cpus_allowed_list:") && (affinity = strip(split(line, ':'; limit = 2)[2]))
        end
    end
    return Dict{String, Any}(
        "hostname" => gethostname(),
        "cpu_model" => isempty(cpu) ? missing : cpu[1].model,
        "cpu_name" => Sys.CPU_NAME,
        "cpu_threads" => Sys.CPU_THREADS,
        "total_memory" => Sys.total_memory(),
        "blas_config" => string(BLAS.get_config()),
        "blas_num_threads" => BLAS.get_num_threads(),
        "julia_threads" => Threads.nthreads(),
        "env" => Dict{String, Any}(name => get(ENV, name, missing)
                                   for name in ("JULIA_NUM_THREADS", "OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS")),
        "cpus_allowed_list" => affinity,
    )
end

"""
    delta_tag(delta)

Return `delta` as written in result keys and file names (`0.02` gives `"0-02"`).
"""
delta_tag(delta) = replace(string(delta), "." => "-")

"""
    part_name(problem, deltas, protocol_deltas)

Return the name of the part of `problem` that solves `deltas`: the problem name
when they are all of `protocol_deltas`, `<problem>_delta_<tag>[_<tag>...]`
otherwise (e.g. `ZLT1_delta_0-02`). It names the per-problem results file and the
provenance record, so that the parts of a problem split by delta never collide.
"""
function part_name(problem, deltas, protocol_deltas)
    issetequal(deltas, protocol_deltas) && return string(problem)
    return string(problem, "_delta_", join(delta_tag.(sort(collect(deltas))), "_"))
end

"""
    options_record(options)

Return the fields of a `MOSolvers` options struct as a `Dict{String, Any}`, so
that the record can be read without `MOSolvers` loaded.
"""
options_record(options) = Dict{String, Any}(string(f) => getfield(options, f) for f in fieldnames(typeof(options)))

"""
    collect_provenance(configs; seed=nothing, protocol_deltas=nothing)

Build the provenance record shared by all problems in `configs`.

# Arguments
- `configs::Vector{<:ExperimentConfig}`: Configurations of the run.
- `seed`: Seed passed to `Random.seed!` by the calling script, if any.
- `protocol_deltas`: Deltas of the experimental protocol, when `configs` solve
  only some of them (partitioned runs); defaults to the deltas of `configs`.

# Returns
- `Dict{String, Any}` with `julia_version`, `git` (per repository: `MOSolvers`,
  `MultiObjectiveProblems`, `AAS2025-PDFreeMO`), `MOSolvers_names`, `project`
  and `manifest` (file contents), `machine` (see `machine_record`),
  `solver_options` (effective options per solver identifier, including the PDFPM
  `step_tolerance_rule`), `deltas` (solved in `configs`), `protocol_deltas`,
  `nrun` and `seed`.
"""
function collect_provenance(configs::Vector{<:ExperimentConfig}; seed = nothing, protocol_deltas = nothing)
    solver_options = Dict{String, Any}()
    for config in configs
        name = string(config.solver_name)
        haskey(solver_options, name) && continue
        solver_options[name] = options_record(get_solver_options(config.solver_name, config.solver_config))
    end
    read_or_missing(path) = isfile(path) ? read(path, String) : missing
    deltas = sort(unique([config.delta for config in configs]))

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
        "machine" => machine_record(),
        "solver_options" => solver_options,
        "deltas" => deltas,
        "protocol_deltas" => isnothing(protocol_deltas) ? deltas : sort(collect(protocol_deltas)),
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

Store `provenance`, completed with the problem name and box, under
`PROVENANCE_KEY/<part>` in the JLD2 file at `filepath` (created if absent), where
`<part>` is `part_name(problem, provenance["deltas"], provenance["protocol_deltas"])`:
the problem name unless only some protocol deltas are solved.

# Throws
- `error`: If the file already holds that provenance record; results of two
  runs must not share a file silently.
"""
function write_provenance(filepath::String, provenance::Dict{String, Any}, problems)
    jldopen(filepath, "a+") do file
        for problem in problems
            part = part_name(problem, provenance["deltas"], get(provenance, "protocol_deltas", provenance["deltas"]))
            key = "$(PROVENANCE_KEY)/$(part)"
            haskey(file, key) && error("$filepath already holds provenance for $part; use another file name.")
            file[key] = merge(provenance, problem_box_record(Symbol(problem)),
                              Dict{String, Any}("problem" => string(problem)))
        end
    end
end

"""
    load_provenance(filepath, problem_name)

Return the provenance record of `problem_name` stored in `filepath`, or
`nothing` when the file has none (files written before provenance was recorded).

# Throws
- `ArgumentError`: If the problem was solved in parts by delta, so that it has
  one record per part; use `load_provenance(filepath, problem_name, delta)`.
"""
function load_provenance(filepath::String, problem_name)
    jldopen(filepath, "r") do file
        key = "$(PROVENANCE_KEY)/$(problem_name)"
        haskey(file, key) && return file[key]
        haskey(file, PROVENANCE_KEY) || return nothing
        prefix = "$(problem_name)_delta_"
        any(startswith(prefix), keys(file[PROVENANCE_KEY])) &&
            throw(ArgumentError("$problem_name was solved in parts by delta; call load_provenance(filepath, $(repr(problem_name)), delta)"))
        return nothing
    end
end

"""
    load_provenance(filepath, problem_name, delta)

Return the provenance record of the run that solved `problem_name` with `delta`
in `filepath`: the record of the whole problem, or of the part holding `delta`
when the problem was solved in parts by delta. Return `nothing` when there is none.
"""
function load_provenance(filepath::String, problem_name, delta)
    jldopen(filepath, "r") do file
        haskey(file, PROVENANCE_KEY) || return nothing
        group = file[PROVENANCE_KEY]
        for part in keys(group)
            (part == string(problem_name) || startswith(part, "$(problem_name)_delta_")) || continue
            record = group[part]
            any(isequal(delta), record["deltas"]) && return record
        end
        return nothing
    end
end
