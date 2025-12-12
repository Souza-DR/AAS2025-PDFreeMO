# AAS2025-PDFreeMO: Numerical Experiments

This repository contains the infrastructure to run, store, and analyze the numerical experiments associated with the manuscript **"A Partially Derivative-Free Proximal Method for Composite Multiobjective Optimization in the Hölder Setting"** ([arXiv:2508.20071](https://doi.org/10.48550/arXiv.2508.20071)).

The goal of this project is to provide a robust, reproducible, and extensible testbed for evaluating the performance of the **PDFPM** algorithm proposed in  
[arXiv:2508.20071](https://doi.org/10.48550/arXiv.2508.20071), and for comparing it against other state-of-the-art multi-objective optimization solvers, namely:

- **CondG** - [https://doi.org/10.1080/02331934.2023.2257709](https://doi.org/10.1080/02331934.2023.2257709)
- **ProxGrad** - [https://doi.org/10.1007/s10589-018-0043-x](https://doi.org/10.1007/s10589-018-0043-x)


---

## Associated Packages

This project relies on two specialized Julia packages developed for multi-objective optimization. These packages provide the core problem definitions and solver implementations used in the experiments.

### [MOProblems.jl](https://github.com/VectorOptimizationGroup/MOProblems.jl)
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

### Step 1: Clone this repository
```bash
git clone https://github.com/Souza-DR/AAS2025-PDFreeMO.git
cd AAS2025-PDFreeMO
```

### Step 2: Activate and instantiate the local environment
We strongly recommend activating the local project environment defined by `Project.toml`.

```bash
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
```

### Step 3: Install unregistered dependencies
Since `MOProblems.jl` and `MOSolvers.jl` are currently unregistered, you must install them directly from their repositories:

```bash
julia --project=. -e '
using Pkg
Pkg.add(url="https://github.com/VectorOptimizationGroup/MOProblems.jl.git")
Pkg.add(url="https://github.com/VectorOptimizationGroup/MOSolvers.jl.git")
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
