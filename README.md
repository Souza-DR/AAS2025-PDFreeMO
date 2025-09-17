# AAS2025-PDFreeMO: Numerical Experiments Repository

This repository contains the infrastructure to run, store, and analyze the numerical experiments associated with the AAS2025 manuscript on a **partially derivative-free proximal-point method (PDFPM)** for multiobjective composite optimization. The goal is to provide a robust, reproducible, and extensible testbed for evaluating multiobjective solvers.

---

## Project structure

- **/src** — Source code of the module `AAS2025PDFreeMO.jl` that orchestrates experiments (configuration types, runners, and I/O helpers).
- **/scripts** — Executable scripts that define and launch benchmarks.
- **/data** — Results directory managed by `DrWatson.jl` (e.g., `data/sims`).
- **/test** — Placeholder for future unit tests of the infrastructure.

---

## Local development dependencies — MOProblems, MOSolvers, MOMetrics

This project **depends on local, unregistered Julia packages under active development**. To run everything correctly, **activate this project** and develop the three packages **in the same environment** from the repository root:

```bash
julia -q --project=. -e '
using Pkg
Pkg.develop([
    PackageSpec(path="/path/to/MOProblems.jl"),
    PackageSpec(path="/path/to/MOSolvers.jl"),
    PackageSpec(path="/path/to/MOMetrics.jl"),
])
Pkg.resolve(); Pkg.precompile(); Pkg.status()'
```

Prefer remote versions instead? Replace `path=` with, for example,
`url="https://github.com/YourUser/MOProblems.jl.git"` (and similarly for the others).

### Quick check

```bash
julia -q --project=. -e 'using MOProblems, MOSolvers, MOMetrics, AAS2025PDFreeMO; println("Environment OK")'
```

---

## Troubleshooting (with local dev deps)

- **Error**: `ERROR: expected package 'MOProblems [...]' to be registered`  
  **Cause**: the active environment does not know your local package path, so `Pkg` attempts to fetch a registered release and fails.  
  **Fix**: run the `Pkg.develop` command above (for **all three** packages) at the repository root.

- **Wrong environment**: ensure you are at the repository root and using `--project=.` (or `Pkg.activate(".")`).

- **Stale/corrupted Manifest (during development)**:
  ```bash
  rm -f Manifest.toml
  julia -q --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile(); Pkg.status()'
  ```

---

## Module `AAS2025PDFreeMO.jl`

The core of this repository is the module `AAS2025PDFreeMO`, which exports configuration/result types and high-level routines to create and execute benchmarks.

### Exported components

**Configuration and result types**

- `ExperimentConfig`: Stores all **input** parameters for one experiment instance (problem, solver, initial point, etc.), **including** precomputed matrices `A` that define the nondifferentiable part `H`. This ensures full reproducibility within each (problem, δ) pair.
- `ExperimentResult`: Stores **output** data from one run (e.g., number of iterations, runtime, final objective value).
- `SolverConfiguration`, `CommonSolverOptions`, `SolverSpecificOptions`: Nested `struct`s that standardize solver options in a clear and extensible way.

**Main functions**

- `generate_experiment_configs(...)`: Builds a vector of `ExperimentConfig` from lists of problems, solvers, deltas, and number of runs.
- `run_experiment(...)`: Executes a vector of `ExperimentConfig` and returns a vector of `ExperimentResult`.
- `run_experiment_with_batch_saving(...)`: Runs experiments with automatic batch saves to reduce data-loss risk.
- `get_solver_options(...)`: Maps a generic `SolverConfiguration` to the solver-specific options expected by `MOSolvers.jl`.
- `datas(...)`: Utility to generate data matrices used in robust problem instances.

---

## Typical workflow

Benchmarks are typically run in three steps, often inside a script under `/scripts`.

### 1) Define benchmark parameters

```julia
using DrWatson
@quickactivate "AAS2025-PDFreeMO"

using .AAS2025PDFreeMO
using Random

# 1) Solver options
const COMMON_OPTIONS = CommonSolverOptions(max_iter=100, opt_tol=1e-6)
const SPECIFIC_OPTIONS = Dict(
    :PDFPM    => SolverSpecificOptions(max_subproblem_iter=50),
    :ProxGrad => SolverSpecificOptions(mu=1.0),
)

# 2) Benchmark sets
const SOLVERS  = [:PDFPM, :ProxGrad]
const PROBLEMS = [:ZDT1, :ZDT2]
const NRUN     = 50
const DELTAS   = [0.0, 0.05]
```

### 2) Generate and run experiments

```julia
function main()
    Random.seed!(42)

    # 3) Build configurations
    configs = generate_experiment_configs(
        PROBLEMS,
        SOLVERS,
        NRUN,
        DELTAS,
        COMMON_OPTIONS;
        solver_specific_options = SPECIFIC_OPTIONS,
    )
    println("Total experiments to run: $(length(configs))")

    # 4) Execute with batch saving
    results = run_experiment_with_batch_saving(
        configs;
        batch_size   = 50,
        filename_base = "zdt_benchmark",
    )

    println("
Benchmark completed. Results saved under: $(datadir("sims"))")
end

main()
```

### 3) Analyze results

Results are automatically saved as JLD2 files under `data/sims/` with a timestamped filename. You can load them later for analysis:

```julia
using DrWatson, JLD2

# Load a specific result file
filepath = datadir("sims", "zdt_benchmark_2025-01-27_14-30-15.jld2")
loaded = jldopen(filepath, "r") do f
    # Access the PDFPM result for problem ZDT1, delta 0.0, first run
    # Layout: solver/problem/delta/run_id
    f["PDFPM/ZDT1/delta_0-0/run_1"]
end

println("Loaded result: ", loaded)
```

**Saved data hierarchy**

- `solver_name/problem_name/delta/run_id`

Where:
- `solver_name`: e.g., `"PDFPM"`, `"ProxGrad"`;
- `problem_name`: e.g., `"ZDT1"`, `"AP2"`;
- `delta`: e.g., `"delta_0-0"` for δ = 0.0;
- `run_id`: per-combination run identifier.

**Batch-saving system**  
`run_experiment_with_batch_saving` incrementally writes partial results and consolidates them into a single timestamped file, providing resilience against interruptions and facilitating long runs.

---

## Reproducibility notes

- **Data management**: We rely on `DrWatson.jl` for standardized paths (e.g., `datadir("sims")`) and clean separation of code and results.
- **Seeding**: Use `Random.seed!` in scripts to ensure consistent runs when desired.
- **Environment**: Keep `Project.toml`/`Manifest.toml` under version control to guarantee reproducibility across machines.

---

## License

See the `LICENSE` file in this repository. If absent, please contact the maintainers regarding licensing.

---

## Citation

If you use this repository in academic work, please cite the associated AAS2025 manuscript on the PDFPM method. A BibTeX entry will be provided upon preprint/publication.