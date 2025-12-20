"""
    CommonSolverOptions{T}

Container for solver-agnostic configuration parameters.

# Fields
- `verbose::Int`: Verbosity level expected by the solver.
- `max_iter::Int`: Maximum number of iterations.
- `opt_tol::T`: Optimality tolerance.
- `ftol::T`: Function tolerance.
- `max_time::T`: Maximum wall-clock time in seconds.
- `print_interval::Int`: Logging interval in iterations.
- `store_trace::Bool`: Whether to store solver trace.
- `stop_criteria::Symbol`: Termination criterion identifier.
"""
struct CommonSolverOptions{T<:Real}
    verbose::Int
    max_iter::Int
    opt_tol::T
    ftol::T
    max_time::T
    print_interval::Int
    store_trace::Bool
    stop_criteria::Symbol
    
    # Inner constructor with defaults.
    function CommonSolverOptions{T}(;
        verbose::Integer = 0,
        max_iter::Integer = 100,
        opt_tol::T = 1e-6,
        ftol::T = 1e-4,
        max_time::T = 3600.0,
        print_interval::Integer = 10,
        store_trace::Bool = false,
        stop_criteria::Symbol = :NormProgress
    ) where T<:Real
        new{T}(verbose, max_iter, opt_tol, ftol, max_time, print_interval, store_trace, stop_criteria)
    end
end

# Convenience outer constructor.
CommonSolverOptions(; kwargs...) = CommonSolverOptions{Float64}(; kwargs...)

"""
    SolverSpecificOptions{T}

Container for solver-specific configuration parameters. Use `nothing` to keep
the solver's default value.

# Fields
- `mu::Union{T, Nothing}`: ProxGrad regularization parameter.
- `epsilon::Union{T, Nothing}`: PDFPM tolerance parameter.
- `sigma::Union{T, Nothing}`: PDFPM penalty parameter.
- `alpha::Union{T, Nothing}`: PDFPM step-size parameter.
- `max_subproblem_iter::Union{Int, Nothing}`: PDFPM subproblem iteration cap.
"""
struct SolverSpecificOptions{T<:Real}
    # ProxGrad specific
    mu::Union{T, Nothing}
    
    # PDFPM specific  
    epsilon::Union{T, Nothing}
    sigma::Union{T, Nothing}
    alpha::Union{T, Nothing}
    max_subproblem_iter::Union{Int, Nothing}
    
    function SolverSpecificOptions{T}(;
        mu::Union{T, Nothing} = nothing,
        epsilon::Union{T, Nothing} = nothing,
        sigma::Union{T, Nothing} = nothing,
        alpha::Union{T, Nothing} = nothing,
        max_subproblem_iter::Union{Int, Nothing} = nothing
    ) where T<:Real
        new{T}(mu, epsilon, sigma, alpha, max_subproblem_iter)
    end
end

SolverSpecificOptions(; kwargs...) = SolverSpecificOptions{Float64}(; kwargs...)

"""
    SolverConfiguration{T}

Bundled configuration for a solver, composed of common and solver-specific
options.
"""
struct SolverConfiguration{T<:Real}
    common_options::CommonSolverOptions{T}
    specific_options::SolverSpecificOptions{T}
end

function SolverConfiguration{T}(common::CommonSolverOptions{T}; kwargs...) where T<:Real
    specific = SolverSpecificOptions{T}(; kwargs...)
    return SolverConfiguration(common, specific)
end

"""
    to_proxgrad_options(config::SolverConfiguration{T}) where T

Convert a normalized configuration into `ProxGrad_options`.
"""
function to_proxgrad_options(config::SolverConfiguration{T}) where T
    common = config.common_options
    specific = config.specific_options
    
    # Use the provided value or fall back to a sensible default.
    mu_val = isnothing(specific.mu) ? T(1.0) : specific.mu
    
    return ProxGrad_options(
        verbose = common.verbose,
        max_iter = common.max_iter,
        opt_tol = common.opt_tol,
        ftol = common.ftol,
        max_time = common.max_time,
        print_interval = common.print_interval,
        store_trace = common.store_trace,
        mu = mu_val,
        stop_criteria = common.stop_criteria
    )
end

"""
    to_pdfpm_options(config::SolverConfiguration{T}) where T

Convert a normalized configuration into `PDFPM_options`.
"""
function to_pdfpm_options(config::SolverConfiguration{T}) where T
    common = config.common_options
    specific = config.specific_options
    
    # Use provided values or fall back to sensible defaults.
    epsilon_val = isnothing(specific.epsilon) ? T(1e-4) : specific.epsilon
    sigma_val = isnothing(specific.sigma) ? T(1.0) : specific.sigma
    alpha_val = isnothing(specific.alpha) ? T(0.1) : specific.alpha
    max_subproblem_iter_val = isnothing(specific.max_subproblem_iter) ? 50 : specific.max_subproblem_iter
    
    return PDFPM_options(
        verbose = common.verbose,
        max_iter = common.max_iter,
        opt_tol = common.opt_tol,
        ftol = common.ftol,
        max_time = common.max_time,
        print_interval = common.print_interval,
        store_trace = common.store_trace,
        epsilon = epsilon_val,
        sigma = sigma_val,
        alpha = alpha_val,
        max_subproblem_iter = max_subproblem_iter_val,
        stop_criteria = common.stop_criteria
    )
end

"""
    to_condg_options(config::SolverConfiguration{T}) where T

Convert a normalized configuration into `CondG_options`.
"""
function to_condg_options(config::SolverConfiguration{T}) where T
    common = config.common_options
    
    return CondG_options(
        verbose = common.verbose,
        max_iter = common.max_iter,
        opt_tol = common.opt_tol,
        ftol = common.ftol,
        max_time = common.max_time,
        print_interval = common.print_interval,
        store_trace = common.store_trace,
        stop_criteria = common.stop_criteria
    )
end

"""
    get_solver_options(solver_name::Symbol, config::SolverConfiguration{T}) where T

Convert a generic `SolverConfiguration` into the solver-specific options
struct (e.g., `PDFPM_options`, `ProxGrad_options`) required by `MOSolvers.jl`.

Dispatches to the appropriate conversion function based on `solver_name`.

# Arguments
- `solver_name::Symbol`: Solver name (e.g., `:PDFPM`).
- `config::SolverConfiguration{T}`: Normalized solver configuration.

# Returns
- A solver-specific options struct from `MOSolvers.jl` (e.g., `PDFPM_options`).

# Throws
- `error`: If `solver_name` is not recognized.
"""
function get_solver_options(solver_name::Symbol, config::SolverConfiguration{T}) where T
    if solver_name == :ProxGrad
        return to_proxgrad_options(config)
    elseif solver_name == :PDFPM || solver_name == :Dfree
        return to_pdfpm_options(config)
    elseif solver_name == :CondG
        return to_condg_options(config)
    else
        error("Unknown solver: $solver_name")
    end
end