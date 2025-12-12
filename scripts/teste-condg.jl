using DrWatson
using MOProblems
using MOSolvers
using Random
@quickactivate "AAS2025-PDFreeMO"
include(srcdir("AAS2025PDFreeMO.jl"))
using .AAS2025PDFreeMO

problem_instance = MOProblems.JOS1()
nvar = problem_instance.nvar
nobj = problem_instance.nobj
l = problem_instance.bounds[1]
u = problem_instance.bounds[2]

# x0 = l .+ (u - l) .* rand(nvar)
x0 = [9.680050848141846, 23.968414911621053]
delta = 0.0
A = datas(nvar, nobj)
A = [[0.6256230799514603 0.5248834255929747; 0.6309408442076742 0.5851203733917759], [0.811402957523026 0.45813487057867197; 0.7738680524266933 0.7083399139214106]]

options = MOSolvers.CondG_options(
    verbose = 3,
    max_iter = 100,
    opt_tol = 1e-6,
    ftol = 1e-4,
    max_time = 3600.0,
    print_interval = 1,
    store_trace = false
)

result = MOSolvers.CondG(x -> safe_evalf_solver(problem_instance, x),
                x -> safe_evalJf_solver(problem_instance, x),
                A,
                delta,
                x0,
                options;
                lb = l, ub = u)

println(result)