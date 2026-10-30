"""
Stationarity merit w₁ of returned points, a measure common to all solvers.

For F = f + h on the box [l, u], with h_j(x) = max{⟨x, z⟩ : -δe ≤ A_j z ≤ δe},

    w₁(x) = max_{y ∈ [l,u]} min_j [∇f_j(x)ᵀ(x - y) + h_j(x) - h_j(y) - ½‖x - y‖²],

the merit w_ℓ of Tanabe et al. (Optim. Lett. 2023, eq. (5)) with ℓ = 1. It is
zero exactly at Pareto critical points and equals -θ of ProxGrad's subproblem
with σ = 1, which is how `merit_w1` computes it.
"""

using LinearAlgebra: dot, norm

"""
Ipopt tolerances tried in turn by `merit_w1`: the first is the target, validated
against `merit_w1_dual` (|Ipopt - dual| ≤ 2.3e-10 at w₁ ≈ 0, growing with
‖∇f‖²); the second is used only when Ipopt fails at the first, which happens
mostly at points far from stationarity.
"""
const MERIT_TOLS = (1e-12, 1e-10)

"""
    merit_params(A, delta, lb, ub)

Return the `MOSolvers.SubProblemParams` of h for the matrices `A`, the
perturbation `delta` and the box [`lb`, `ub`], as `ProxGrad` builds them:
Z_j = {z : -δe ≤ A_j z ≤ δe} is stored as [A_j; -A_j] z ≤ δe.

Build it once per (problem, delta) and reuse it: `MOSolvers.evalh!` caches its
LP models per `SubProblemParams` object.
"""
function merit_params(A::AbstractVector{<:AbstractMatrix}, delta::Real, lb::AbstractVector, ub::AbstractVector)
    A2n = [Matrix{Float64}([Aj; -Aj]) for Aj in A]
    b2n = [fill(Float64(delta), size(Aj, 1)) for Aj in A2n]
    return MOSolvers.SubProblemParams(A2n, b2n, Vector{Float64}(lb), Vector{Float64}(ub))
end

"""
    merit_objective(x, Jf, hx, y, params)

Return min_j [∇f_j(x)ᵀ(x - y) + h_j(x) - h_j(y)] - ½‖x - y‖², the function that
w₁(x) maximizes over y, with `hx` = h(x) and h(y) evaluated exactly by
`MOSolvers.evalh!`; `NaN` if that evaluation fails. Any feasible `y` gives a lower
bound of w₁(x).
"""
function merit_objective(x::AbstractVector, Jf::AbstractMatrix, hx::AbstractVector, y::AbstractVector,
                         params::MOSolvers.SubProblemParams)
    hy = similar(hx)
    ok, _ = MOSolvers.evalh!(hy, Vector{Float64}(y), params)
    ok || return NaN
    d = x - y
    return minimum(Jf * d .+ hx .- hy) - dot(d, d) / 2
end

"""
    merit_w1(x, Jf, params; tols=MERIT_TOLS, max_iter=10_000, max_time=60.0, hx=nothing)

Compute w₁ at `x`, where `Jf` is the Jacobian of f at `x` and `params` comes from
`merit_params`, by solving ProxGrad's subproblem (`MOSolvers.subproblem_proxgrad`)
with σ = 1. The Ipopt tolerances in `tols` are tried in turn until one succeeds.
`max_iter` and `max_time` (seconds) are Ipopt's limits, larger than the
solvers' (3000, 5 s) so that a hard but solvable subproblem does not fail, and
a slow machine rarely changes the outcome. h(x) comes from `MOSolvers.evalh!`
unless given as `hx`.

# Returns
A named tuple with
- `w1`: -θ of the subproblem (`NaN` when `success` is false);
- `y`: its solution y*;
- `success`: whether h(x) was evaluated and Ipopt converged at some tolerance; a
  failure is reported, never turned into w₁ = 0;
- `tol`: the tolerance that succeeded (`NaN` on failure);
- `message`: Ipopt's status of the last attempt, or the failure;
- `primal`: `merit_objective` at y*, a lower bound of w₁ that does not rely on
  Ipopt's τ (the gap `w1 - primal` measures the inaccuracy of the solve);
- `h_dropped`: δ > 0 and some |h_j(x)| ≤ max(tol, 1e-14). The subproblem then
  omits h_j(y) ≥ 0 for that j, as in ProxGrad, so `w1` is an upper bound of w₁
  (up to that tolerance); `primal` still evaluates h(y*);
- `hx`: the h(x) used.

`evalh!` solves an LP with HiGHS's default tolerances: when x is tiny
(‖x‖ ≲ 1e-7 in the runs seen) it can return h_j(x) = 0 although h_j(x) > 0, or
fail; `hx` allows checking it.

`w1` can be slightly negative at a stationary point (Ipopt's accuracy); it is
returned as computed.
"""
function merit_w1(x::AbstractVector, Jf::AbstractMatrix, params::MOSolvers.SubProblemParams;
                  tols = MERIT_TOLS, max_iter::Integer = 10_000, max_time::Real = 60.0,
                  hx::Union{Nothing, AbstractVector} = nothing)
    x = Vector{Float64}(x)
    Jf = Matrix{Float64}(Jf)
    m = size(Jf, 1)
    failure(message) = (w1 = NaN, y = fill(NaN, length(x)), success = false, tol = NaN,
                        message = message, primal = NaN, h_dropped = false, hx = fill(NaN, m))
    if hx === nothing
        hx = zeros(m)
        ok, message = MOSolvers.evalh!(hx, x, params)
        ok || return (; failure("evalh! failed at x: " * message)..., hx = hx)
    else
        hx, message = Vector{Float64}(hx), ""
    end
    perturbed = !any(any(iszero, b) for b in params.b)  # evalh! sets h = 0 otherwise
    for tol in tols
        theta, y, success, message = MOSolvers.subproblem_proxgrad(x, Jf, hx, params; sigma = 1.0,
                                                                   tol = Float64(tol), max_iter = Int(max_iter),
                                                                   max_time = max_time)
        (success && isfinite(theta)) || continue
        return (w1 = -theta, y = y, success = true, tol = Float64(tol), message = message,
                primal = merit_objective(x, Jf, hx, y, params),
                h_dropped = perturbed && any(abs(hj) <= max(tol, 1e-14) for hj in hx), hx = hx)
    end
    return failure("subproblem: " * message)
end

"""
    merit_w1_dual(x, Jf, lb, ub)

Compute w₁ at `x` for h = 0 (δ = 0) and m ≤ 3 objectives through its dual

    w₁(x) = min_{λ ∈ Δ} φ(λ),  φ(λ) = g_λᵀ(x - y_λ) - ½‖x - y_λ‖²,

with g_λ = Σ λ_j ∇f_j(x) and y_λ = P_[lb,ub](x - g_λ) (min-max exchange by Sion's
theorem: the simplex Δ is compact and the inner function is concave in y and
linear in λ). φ is convex and differentiable with ∂φ/∂λ_j = ∇f_j(x)ᵀ(x - y_λ).

- m = 1: φ(1).
- m = 2: λ = (t, 1 - t); bisection on the nondecreasing derivative in t down to
  adjacent floating-point numbers.
- m = 3: λ = (a, 1 - t - a, t). For fixed t, the minimum over a ∈ [0, 1 - t] is
  the m = 2 search; the result ψ(t) is convex (partial minimization of a convex
  function over a set that depends linearly on t), minimized by golden-section
  search over t ∈ [0, 1] until the bracket stops shrinking.

Every φ evaluated is an upper bound of w₁; the smallest is returned, with the
minimizing λ.

# Throws
- `ArgumentError`: If `Jf` has more than 3 rows.
"""
function merit_w1_dual(x::AbstractVector, Jf::AbstractMatrix, lb::AbstractVector, ub::AbstractVector)
    m = size(Jf, 1)
    m <= 3 || throw(ArgumentError("merit_w1_dual handles m ≤ 3 objectives, got $m"))
    function phi(λ)
        g = Jf' * λ
        d = x - clamp.(x - g, lb, ub)
        return dot(g, d) - dot(d, d) / 2, Jf * d
    end
    m == 1 && return (w1 = first(phi([1.0])), lambda = [1.0])

    # min over a ∈ [0, s] of φ(base + a(e₁ - e₂)), with base = (0, s, 1 - s) (or (0, 1) for m = 2)
    function segment_min(s)
        lam(a) = m == 2 ? [a, s - a] : [a, s - a, 1 - s]
        slope(a) = (grad = phi(lam(a))[2]; grad[1] - grad[2])
        lo, hi = 0.0, s
        if slope(lo) >= 0
            hi = lo
        elseif slope(hi) <= 0
            lo = hi
        else
            while true
                mid = (lo + hi) / 2
                (mid == lo || mid == hi) && break
                slope(mid) < 0 ? (lo = mid) : (hi = mid)
            end
        end
        vlo, vhi = first(phi(lam(lo))), first(phi(lam(hi)))
        return vlo <= vhi ? (vlo, lam(lo)) : (vhi, lam(hi))
    end
    if m == 2
        w1, lambda = segment_min(1.0)
        return (; w1, lambda)
    end

    # m = 3: golden-section search on ψ(t) = segment_min(1 - t). Names differ from
    # those of the closures above, which would otherwise capture them.
    best = Ref((Inf, Float64[]))
    psi(t) = (r = segment_min(1 - t); r[1] < best[][1] && (best[] = r); r[1])
    psi(0.0); psi(1.0)
    ratio = (sqrt(5) - 1) / 2
    tlo, thi = 0.0, 1.0
    t1, t2 = thi - ratio * (thi - tlo), tlo + ratio * (thi - tlo)
    psi1, psi2 = psi(t1), psi(t2)
    for _ in 1:200  # the bracket reaches floating-point resolution after ~80 steps
        width = thi - tlo
        if psi1 <= psi2
            thi, t2, psi2 = t2, t1, psi1
            t1 = thi - ratio * (thi - tlo); psi1 = psi(t1)
        else
            tlo, t1, psi1 = t1, t2, psi2
            t2 = tlo + ratio * (thi - tlo); psi2 = psi(t2)
        end
        (thi - tlo >= width || !(tlo <= t1 <= thi) || !(tlo <= t2 <= thi)) && break
    end
    return (w1 = best[][1], lambda = best[][2])
end
