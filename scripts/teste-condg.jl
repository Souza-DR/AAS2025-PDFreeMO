using DrWatson
using MOProblems
using MOSolvers
using Random
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

problem_instance = MOProblems.AP2()
nvar = problem_instance.nvar
nobj = problem_instance.nobj
l = problem_instance.bounds[1]
u = problem_instance.bounds[2]

x0 = l .+ (u - l) .* rand(nvar)
delta = 0.0
A = datas(nvar, nobj, delta)

options = MOSolvers.CondG_options(
    verbose = 1,
    max_iter = 100,
    opt_tol = 1e-6,
    ftol = 1e-4,
    max_time = 3600.0,
    print_interval = 1,
    store_trace = false,
    stop_criteria = :proxgrad
)

result = MOSolvers.CondG(x -> safe_evalf_solver(problem_instance, x),
                x -> safe_evalJf_solver(problem_instance, x),
                A,
                delta,
                x0,
                options;
                lb = l, ub = u)

println(result)