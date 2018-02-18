export weigthed_mean, plot_trajectories, scatter_particles, logsumexp!, smoothed_mean, smoothed_cov, smoothed_trajs, plot_priors

function logsumexp!(w)
    offset = maximum(w)
    nc = sum(w->exp(w-offset), w)
    nc = log(nc) + offset
    w .-= nc
    nc
end

function weigthed_mean(x,w)
    xh = zeros(size(x[1]))
    @inbounds @simd  for i = eachindex(x)
        xh .+= x[i].*exp(w[i])
    end
    return xh
end
weigthed_mean(s) = weigthed_mean(s.x,s.w)
weigthed_mean(pf::ParticleFilter) = weigthed_mean(pf.state)

function smoothed_mean(xb)
    M,T = size(xb)
    n = length(xb[1])
    xbm = sum(xb,1)[:] ./ M
    reinterpret(Float64, xbm, (n,T))
end

function smoothed_cov(xb)
    M,T = size(xb)
    n = length(xb[1])
    xbc = [cov(reinterpret(Float64, xb[:,t], (n,M))) for t = 1:T]
end

function smoothed_trajs(xb)
    M,T = size(xb)
    n = length(xb[1])
    reinterpret(Float64, xb, (n,M,T))
end

function plot_trajectories(pf,y,xt)
    xa = reinterpret(Float64, particles(pf), (length(particles(pf)[1]), length(particles(pf))))
    scatter(xa[1,:],xa[2,:], title="Particles", reuse=true, xlims=(-15,15), ylims=(-15,15), grid=false, size=(1000,1000))
    scatter!([y[1]], [y[2]], m = (:red, 5))
    scatter!([xt[1]], [xt[2]], m = (:green, 5))
    sleep(0.2)
end

function scatter_particles(pf,xt,t; kwargs...)
    dim, T = size(xt)
    np = num_particles(pf)
    xa = reinterpret(Float64, pf.s.x, (dim, np))
    plot(xt', title="Particles", reuse=true,  grid=false, layout=dim, kwargs...)
    plot!(y', l = (:red, 2))
    I = t*ones(np)
    for i = 1:dim
        scatter!(I, xa[i,:], subplot=i)
    end
    sleep(0.2)
end

function plot_priors(priors; kwargs...)
    fig = plot(priors[1]; kwargs...)
    for i = 2:length(priors)
        plot!(priors[i])
    end
    fig
end