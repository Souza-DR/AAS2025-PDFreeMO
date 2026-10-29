# AAS2025-PDFreeMO: Numerical Experiments

This repository contains the infrastructure to run, store, and analyze the numerical experiments associated with the manuscript **"A Partially Derivative-Free Proximal Method for Composite Multiobjective Optimization in the Hölder Setting"** ([arXiv:2508.20071](https://doi.org/10.48550/arXiv.2508.20071)).

The goal of this project is to provide a robust, reproducible, and extensible testbed for evaluating the performance of the **PDFPM** algorithm proposed in  
[arXiv:2508.20071](https://doi.org/10.48550/arXiv.2508.20071), and for comparing it against other state-of-the-art multi-objective optimization solvers, namely:

- **CondG** - [https://doi.org/10.1080/02331934.2023.2257709](https://doi.org/10.1080/02331934.2023.2257709)
- **ProxGrad** - [https://doi.org/10.1007/s10589-018-0043-x](https://doi.org/10.1007/s10589-018-0043-x)


---

## Associated Packages

This project relies on two specialized Julia packages developed for multi-objective optimization. These packages provide the core problem definitions and solver implementations used in the experiments.

### [MultiObjectiveProblems.jl](https://github.com/VectorOptimizationGroup/MultiObjectiveProblems.jl)
Benchmark library of vector-valued optimization problems in Julia, with analytic per-objective gradients, filtering functions, and a unified interface for testing and comparisons of multi-objective solvers.

### [MOSolvers.jl](https://github.com/VectorOptimizationGroup/MOSolvers.jl)
A Julia package for solving multi-objective optimization problems with composite structure ($F = f + h$). Implements Conditional Gradient, Proximal Gradient, and Partially Derivative-Free algorithms that operate directly on the vector-valued objective, without scalarization or heuristics (direct / vector-optimization methods).

---

## Repository Structure

- **/src** – Source code of the module `AAS2025PDFreeMO.jl` that orchestrates experiments (configuration types, runners, and I/O helpers).
- **/scripts** – Executable scripts that launch benchmarks and generate plots.

---

## Installation

### Requirements
- **Julia ≥ 1.11**

### Step 1: Clone the unregistered dependencies
```bash
git clone https://github.com/VectorOptimizationGroup/MultiObjectiveProblems.jl.git
git clone https://github.com/VectorOptimizationGroup/MOSolvers.jl.git
```

### Step 2: Clone this repository
```bash
git clone https://github.com/Souza-DR/AAS2025-PDFreeMO.git
cd AAS2025-PDFreeMO
```

### Step 3: Add the local packages to this project
```bash
julia --project=. -e '
using Pkg
Pkg.add(path="../MultiObjectiveProblems.jl")
Pkg.add(path="../MOSolvers.jl")
Pkg.instantiate()
Pkg.precompile()
'
```

---

## Running the Benchmarks

All executable scripts are located in the `scripts/` directory.

### 1. Run the Main Experiments
Use the `run_all_problems.jl` script to execute the full test suite. This script runs the solvers on the configured test problems, automatically creates the `data/sims` directory if it does not exist, and saves the results as `.jld2` files in this directory.

```bash
julia --project=. scripts/run_all_problems.jl
```

#### Contents of the results files
Runs are stored under `solver/problem/delta_<δ>/run_<id>` as `ExperimentResult`s, which record `converged`, the solver's termination `status` and `message`, and the PDFPM `step_tolerance_rule` (`:none` for ProxGrad and CondG). The solver identifiers are `:PDFPM` (rule `:epsilon`, as in the submitted manuscript), `:PDFPM_trace_scaled` (rule `:trace_scaled`, revised Steps 3–4), `:Dfree` (PDFPM without the Jacobian, rule `:epsilon`, same PDFPM options as `:PDFPM`), `:ProxGrad` and `:CondG`. The default list leaves `:Dfree` out: it belongs to a separate finite-difference experiment. Problems without registered bounds use `MultiObjectiveProblems.recommended_bounds`, both in the runs and in the objective-space plots.

Each result also holds the per-iteration traces of the solver (`x_trace`, `Fval_trace`, `abs_theta_trace`, `norm_progress_trace` and, for PDFPM, `sigma_trace` and `max_tr_B_trace`), filled according to `store_level` in `CommonSolverOptions`. The benchmark uses `:low`, which keeps every trace except `x_trace`. Results written before these fields existed can still be read by the analysis functions.

Each file also holds `_provenance/<problem>`: the commit and dirty state of `MOSolvers.jl`, `MultiObjectiveProblems.jl` and this repository, the Julia version, the full `Project.toml` and `Manifest.toml`, the machine (`"machine"`: host name, CPU model and target, logical CPUs, memory, BLAS configuration and threads, Julia threads, the `JULIA_NUM_THREADS`/`OPENBLAS_NUM_THREADS`/`OMP_NUM_THREADS` variables and the CPU affinity; results are not bit-for-bit reproducible across CPUs), the effective solver options, the solved `deltas` and the `protocol_deltas`, the seed and the box. Read it with `AAS2025PDFreeMO.load_provenance(filepath, problem)`. A problem solved in parts by delta (below) has one record per part, `_provenance/<problem>_delta_<δ>…`; `load_provenance(filepath, problem)` then throws, and `load_provenance(filepath, problem, delta)` returns the record of the part that solved `delta` (it also works for whole problems).

#### Partitioned runs on several cores
The benchmark can be split by problem, or by (problem, delta), over independent processes without changing any random draw: every worker seeds once, generates the configurations of **all** problems and deltas in protocol order and solves only its own (`main(; run_problems, run_deltas, worker, nworkers)`), so its initial points and `A` matrices are those of the sequential run, and the four solvers of an instance run on the same core. A problem split by delta is saved as `<problem>_delta_<δ>….jld2` in `problems/`. Each worker writes to its own directory; the partition is stored in the provenance record under `"partition"`.

- `scripts/assignments/*.tsv`: a `<worker><TAB><problem>` line assigns every delta of a problem; `<worker><TAB><problem><TAB><delta>` lines split it by delta. Every (problem, delta) of the protocol must have exactly one worker, a problem is given either way but not both, and a delta must be a protocol value exactly. `balanced_12_neuroniop_zlt1_by_delta.tsv` (12 workers, ZLT1 split by delta) is the assignment for `neuroniop`; its header gives the weights and the estimated makespan.
- `scripts/run_worker.jl <assignment.tsv> <worker> <outdir> [nrun]`: one worker; logs `uptime`, `who` and the busy processes of other users before each problem, and the wall time of each problem (`[problem-time]` lines, with the solved deltas).
- `scripts/launch_partitioned.sh <label> <assignment.tsv> [nrun]`: starts every worker of the file detached from the shell (`setsid nohup`), worker `k` pinned to CPU `k-1` with `JULIA_NUM_THREADS=OPENBLAS_NUM_THREADS=OMP_NUM_THREADS=1`. It expects the three repositories, a Julia installation (`julia-1.12.1`) and an instantiated depot (`depot`) as siblings in one directory, and writes `results/<label>/` there (`worker_<k>/`, `logs/`, `launch.txt`, `pids.txt`). It also starts `scripts/snapshot_results.sh`, which copies `results/<label>` to `SNAPSHOT_DIR/<label>` (default `~/f5-snapshots`, meant to be a persistent home) every `SNAPSHOT_SECONDS` (default 1800) while a worker is alive and once more after the last worker exits, so that the final copy holds complete files; `SNAPSHOT_SECONDS=0` disables it.
- `scripts/sync_results.sh <remote_results_dir> <local_dir> [interval]`: run on the local machine; pulls the results with incremental `rsync` until the remote workers end, then once more.

- `scripts/merge_partitioned.jl <results_dir> <output.jld2>`: merges the `worker_*/all_results_*.jld2` files of a run into one file, which the analysis scripts read (put it at the top of `data/sims`). A key present in two files aborts the merge with nothing written, so no result or provenance record is overwritten; the protocol (problem, delta) pairs without results are listed. `append_from_jld2` likewise refuses to overwrite an entry.

### 2. Generate Performance Profiles
After the experiments complete, use `create_performance_profiles.jl` to process the results and generate performance profile plots. The figures will be saved to `data/plots/PP`.

```bash
julia --project=. scripts/create_performance_profiles.jl
```

### 3. Additional Analysis
There are other utility scripts available in `scripts/` for specific analyses:
- `create_delta_comparison_plots.jl`: Compare performance across different $\delta$ values.
- `generate_objective_space_plots.jl`: Visualize the objective space for bi-objective problems.
- `generate_trajectories.jl`: Plot the optimization trajectories of the solvers under analysis for bi-objective problems.

---

## Citation

If you use this repository or the associated algorithms in your research, please cite the manuscript:

> **[arXiv:2508.20071](https://doi.org/10.48550/arXiv.2508.20071)**: A Partially Derivative-Free Proximal Method for Composite Multiobjective Optimization in the Hölder Setting.
