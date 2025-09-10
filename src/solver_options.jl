"""
Estrutura para armazenar parâmetros comuns a todos os solvers
"""
struct CommonSolverOptions{T<:Real}
    # Parâmetros comuns
    verbose::Int
    max_iter::Int
    opt_tol::T
    ftol::T
    max_time::T
    print_interval::Int
    store_trace::Bool
    stop_criteria::Symbol
    
    # Constructor com valores padrão
    function CommonSolverOptions{T}(;
        verbose::Integer = 0,
        max_iter::Integer = 100,
        opt_tol::T = 1e-6,
        ftol::T = 1e-4,
        max_time::T = 3600.0,
        print_interval::Integer = 10,
        store_trace::Bool = false,
        stop_criteria::Symbol = :proxgrad
    ) where T<:Real
        new{T}(verbose, max_iter, opt_tol, ftol, max_time, print_interval, store_trace, stop_criteria)
    end
end

# Constructor conveniente
CommonSolverOptions(; kwargs...) = CommonSolverOptions{Float64}(; kwargs...)

"""
Estrutura para parâmetros específicos de cada solver
"""
struct SolverSpecificOptions{T<:Real}
    # ProxGrad específicos
    mu::Union{T, Nothing}
    
    # PDFPM específicos  
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
Configuração completa para um solver
"""
struct SolverConfiguration{T<:Real}
    common_options::CommonSolverOptions{T}
    specific_options::SolverSpecificOptions{T}
end

function SolverConfiguration{T}(common::CommonSolverOptions{T}; kwargs...) where T<:Real
    specific = SolverSpecificOptions{T}(; kwargs...)
    return SolverConfiguration(common, specific)
end

# =======================================================================================
# FUNÇÕES DE MAPEAMENTO PARA CADA SOLVER
# =======================================================================================

"""
Converte configuração padronizada para ProxGrad_options
"""
function to_proxgrad_options(config::SolverConfiguration{T}) where T
    common = config.common_options
    specific = config.specific_options
    
    # Usar valor específico se fornecido, senão usar padrão
    mu_val = isnothing(specific.mu) ? T(1.0) : specific.mu
    
    return ProxGrad_options(
        verbose = common.verbose,
        max_iter = common.max_iter,
        opt_tol = common.opt_tol,
        ftol = common.ftol,
        max_time = common.max_time,
        print_interval = common.print_interval,
        store_trace = common.store_trace,
        stop_criteria = common.stop_criteria,
        mu = mu_val
    )
end

"""
Converte configuração padronizada para PDFPM_options
"""
function to_pdfpm_options(config::SolverConfiguration{T}) where T
    common = config.common_options
    specific = config.specific_options
    
    # Usar valores específicos se fornecidos, senão usar padrões
    epsilon_val = isnothing(specific.epsilon) ? T(1e-10) : specific.epsilon
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
        stop_criteria = common.stop_criteria,
        epsilon = epsilon_val,
        sigma = sigma_val,
        alpha = alpha_val,
        max_subproblem_iter = max_subproblem_iter_val
    )
end

"""
Converte configuração padronizada para CondG_options
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

Converte um `SolverConfiguration` genérico para a `struct` de opções específica 
do solver (`PDFPM_options`, `ProxGrad_options`, etc.) exigida pelo pacote `MOSolvers.jl`.

Atua como um dispatcher, chamando a função de conversão apropriada com base no 
`solver_name`.

# Arguments
- `solver_name::Symbol`: O nome do solver (e.g., `:PDFPM`).
- `config::SolverConfiguration{T}`: A configuração padronizada do solver.

# Returns
- Uma `struct` de opções específica do `MOSolvers.jl` (e.g., `PDFPM_options`).

# Throws
- `error`: Se o `solver_name` não for reconhecido.
"""
function get_solver_options(solver_name::Symbol, config::SolverConfiguration{T}) where T
    if solver_name == :ProxGrad
        return to_proxgrad_options(config)
    elseif solver_name == :PDFPM
        return to_pdfpm_options(config)
    elseif solver_name == :CondG
        return to_condg_options(config)
    else
        error("Solver desconhecido: $solver_name")
    end
end