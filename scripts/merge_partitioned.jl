"""
Merge the results of a partitioned run into one file for the analysis scripts.

    julia --project=. scripts/merge_partitioned.jl <results_dir> <output.jld2>

`results_dir` is `results/<label>` of `launch_partitioned.sh`, or its local copy
made by `sync_results.sh`; its `worker_*/all_results_*.jld2` files (one per
worker) are merged into `output.jld2`, which must not exist. Results
(`solver/problem/delta_<δ>/run_<id>`) and provenance records
(`_provenance/<part>`, one per problem or per part of a problem split by delta)
keep their keys. A key found in two files is an error and nothing is written,
so no result or provenance record is ever overwritten. The (problem, delta)
pairs of the protocol (from the `partition` of the provenance records) that no
record covers are printed, so an incomplete run shows.
"""

using DrWatson
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO
using JLD2

"""
    leaf_keys(filepath)

Return the result keys (`solver/problem/delta/run`) and the provenance keys
(`_provenance/<part>`) of a results file, without loading the results.
"""
function leaf_keys(filepath::AbstractString)
    jldopen(filepath, "r") do file
        results, records = String[], String[]
        for top in keys(file)
            if top == AAS2025PDFreeMO.PROVENANCE_KEY
                append!(records, "$top/$part" for part in keys(file[top]))
                continue
            end
            for problem in keys(file[top]), delta in keys(file[top][problem]), run in keys(file[top][problem][delta])
                push!(results, "$top/$problem/$delta/$run")
            end
        end
        return results, records
    end
end

"""
    worker_files(results_dir)

Return the `all_results_*.jld2` file of every `worker_*` directory of `results_dir`.

# Throws
- `ErrorException`: If there is no worker directory, or one of them does not hold exactly one such file.
"""
function worker_files(results_dir::AbstractString)
    dirs = filter(d -> startswith(basename(d), "worker_") && isdir(d), readdir(results_dir; join = true))
    isempty(dirs) && error("No worker_* directory in $results_dir")
    return map(dirs) do dir
        files = filter(f -> startswith(f, "all_results_") && endswith(f, ".jld2"), readdir(dir))
        length(files) == 1 || error("$dir must hold exactly one all_results_*.jld2, found $files")
        joinpath(dir, only(files))
    end
end

"""
    uncovered_pairs(filepath)

Return the protocol (problem, delta) pairs that no provenance record of the
merged file covers. The protocol is read from the records themselves
(`partition["problems"]` and `protocol_deltas`); records written before these
fields existed count as whole problems named by their key.
"""
function uncovered_pairs(filepath::AbstractString)
    jldopen(filepath, "r") do file
        group = file[AAS2025PDFreeMO.PROVENANCE_KEY]
        records = Dict(part => group[part] for part in keys(group))
        problems = unique(vcat([haskey(r, "partition") ? r["partition"]["problems"] : [get(r, "problem", part)]
                                for (part, r) in records]...))
        deltas = unique(vcat([get(r, "protocol_deltas", r["deltas"]) for r in values(records)]...))
        covered = Set((get(r, "problem", part), delta) for (part, r) in records for delta in r["deltas"])
        return [(problem, delta) for problem in problems for delta in deltas if (problem, delta) ∉ covered]
    end
end

function merge_main(args)
    length(args) == 2 || error("usage: merge_partitioned.jl <results_dir> <output.jld2>")
    results_dir, output = args
    ispath(output) && error("$output already exists; choose another name")
    sources = worker_files(results_dir)

    # Check every key before writing, so that a conflict leaves no partial output.
    owner = Dict{String, String}()
    for source in sources
        results, records = leaf_keys(source)
        for key in vcat(results, records)
            haskey(owner, key) && error("$key is in both $(owner[key]) and $source; nothing written")
            owner[key] = source
        end
        println("[merge] $source: $(length(results)) results, $(length(records)) provenance records")
    end

    try
        foreach(source -> AAS2025PDFreeMO.append_from_jld2(output, source), sources)
    catch
        rm(output; force = true)
        rethrow()
    end
    results, records = leaf_keys(output)
    println("[merge] $output: $(length(results)) results, $(length(records)) provenance records")
    uncovered = uncovered_pairs(output)
    isempty(uncovered) || println("[merge] WARNING: $(length(uncovered)) (problem, delta) pairs without results: $uncovered")
end

if abspath(PROGRAM_FILE) == @__FILE__
    merge_main(ARGS)
end
