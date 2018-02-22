
abstract type AbstractFilter end
abstract type AbstractKalmanFilter <: AbstractFilter end
abstract type AbstractParticleFilter <: AbstractFilter end


@with_kw mutable struct KalmanFilter{AT,BT,CT,DT,R1T,R2T,R2DT,D0T,XT,RT} <: AbstractKalmanFilter
    A::AT
    B::BT
    C::CT
    D::DT
    R1::R1T
    R2::R2T
    R2d::R2DT
    d0::D0T
    x::XT
    R::RT
    t::Ref{Int} = Ref(1)
end

"""
KalmanFilter(A,B,C,D,R1,R2,d0=MvNormal(R1))
"""
function KalmanFilter(A,B,C,D,R1,R2,d0=MvNormal(R1))
    KalmanFilter(A,B,C,D,R1,R2,MvNormal(R2), d0, Vector(d0.μ), d0.Σ.mat, Ref(1))
end

struct PFstate{PT<:AbstractArray, FT<:AbstractFloat}
    x::Vector{PT}
    xprev::Vector{PT}
    w::Vector{FT}
    j::Vector{Int64}
    bins::Vector{Float64}
    t::Ref{Int}
end

@with_kw struct ParticleFilter{ST,FT,GT,FDT,GDT,IDT,RST<:DataType} <: AbstractParticleFilter
    state::ST
    dynamics::FT
    measurement::GT
    dynamics_density::FDT
    measurement_density::GDT
    initial_density::IDT
    resample_threshold::Float64 = 0.1
    resampling_strategy::RST = ResampleSystematic
end


"""
ParticleFilter(num_particles, dynamics::Function, measurement::Function, dynamics_density, measurement_density, initial_density)
"""
function ParticleFilter(N::Integer, dynamics::Function, measurement::Function, dynamics_density, measurement_density, initial_density)
    xprev = Vector{SVector{length(initial_density),eltype(initial_density)}}([rand(initial_density) for n=1:N])
    x = deepcopy(xprev)
    w = fill(log(1/N), N)
    s = PFstate(x,xprev,w, Vector{Int}(N), Vector{Float64}(N),Ref(1))
    nf = numargs(dynamics)
    if nf < 3
        f = (x,u,t,p) -> dynamics(x,u)
    elseif nf < 4
        f = (x,u,t,p) -> dynamics(x,u,t)
    else
        f = dynamics
    end

    ng = numargs(measurement)
    if ng < 3
        g = (x,u,t,p) -> measurement(x,u)
    elseif ng < 4
        g = (x,u,t,p) -> measurement(x,u,t)
    else
        g = measurement
    end

    ParticleFilter(state = s, dynamics = f, measurement = g,
    dynamics_density=dynamics_density, measurement_density=measurement_density,
    initial_density=initial_density)
end


function measurement_equation!(pf, y, t, d=pf.measurement_density)
    x,w,g = pf.state.x, pf.state.w, pf.measurement
    @inbounds for i = 1:num_particles(pf)
        w[i] += logpdf(d, Vector(y-g(x[i],t)))
        w[i] = ifelse(w[i] < -1000, -1000, w[i])
    end
    w
end

function propagate_particles!(pf::ParticleFilter,u,j::Vector{Int}, t, d=pf.dynamics_density)
    f = pf.dynamics
    x,xp = pf.state.x, pf.state.xprev
    noise = zeros(length(x[1]))
    @inbounds for i = eachindex(x)
        x[i] =  f(xp[j[i]] ,u, t) + rand!(d, noise)
    end
    x
end

function propagate_particles!(pf::ParticleFilter,u, t, d=pf.dynamics_density)
    f = pf.dynamics
    x,xp = pf.state.x, pf.state.xprev
    noise = zeros(length(x[1]))
    @inbounds for i = eachindex(x)
        x[i] =  f(xp[i] ,u, t) + rand!(d, noise)
    end
    x
end


function propagate_particles(pf::ParticleFilter,u, t, d=pf.dynamics_density)
    f= pf.dynamics
    xp = pf.state.xprev
    x = similar(xp)
    noise = zeros(length(x[1]))
    @inbounds for i = eachindex(x)
        x[i] =  f(xp[i] ,u, t) + rand!(d, noise)
    end
    x
end


# Advanced =================================================================================



@with_kw struct AdvancedParticleFilter{ST,FT,GT,FDT,IDT,RST<:DataType} <: AbstractParticleFilter
    state::ST
    dynamics::FT
    measurement::GT
    dynamics_density::FDT = Normal()
    initial_density::IDT
    resample_threshold::Float64 = 0.5
    resampling_strategy::RST = ResampleSystematic
end


"""
ParticleFilter(num_particles, dynamics::Function, measurement::Function, initial_density)
"""
function AdvancedParticleFilter(N::Integer, dynamics::Function, measurement::Function, dynamics_density, initial_density)
    xprev = Vector{SVector{length(initial_density),eltype(initial_density)}}([rand(initial_density) for n=1:N])
    x = deepcopy(xprev)
    w = fill(log(1/N), N)
    s = PFstate(x,xprev,w, Vector{Int}(N), Vector{Float64}(N),Ref(1))

    AdvancedParticleFilter(state = s, dynamics = dynamics, measurement = measurement, dynamics_density=dynamics_density,
    initial_density=initial_density)
end


function measurement_equation!(pf::AdvancedParticleFilter, y, t)
    g = pf.measurement
    w = weights(pf)
    x = particles(pf)
    @inbounds for i = 1:num_particles(pf)
        w[i] += g(x[i],y,t)
        w[i] = ifelse(w[i] < -1000, -1000, w[i])
    end
    w
end

function propagate_particles!(pf::AdvancedParticleFilter, u, j, t::Int, noise::Bool=true)
    f = pf.dynamics
    x,xp = pf.state.x, pf.state.xprev
    @inbounds for i = eachindex(x)
        x[i] =  f(xp[j[i]] ,u, t, noise)
    end
    x
end

function propagate_particles!(pf::AdvancedParticleFilter, u, t::Int, noise::Bool=true)
    f = pf.dynamics
    x,xp = pf.state.x, pf.state.xprev
    @inbounds for i = eachindex(x)
        x[i] =  f(xp[i] ,u, t, noise)
    end
    x
end


function propagate_particles(pf::AdvancedParticleFilter, u, t::Int, noise::Bool=true)
    f = pf.dynamics
    xp = pf.state.xprev
    x = similar(xp)
    @inbounds for i = eachindex(x)
        x[i] =  f(xp[i] ,u, t, noise)
    end
    x
end


# ==========================================================================================

sample_state(kf::AbstractKalmanFilter) = rand(kf.d0)
sample_state(pf::AbstractParticleFilter) = rand(pf.initial_density)

sample_state(kf::AbstractKalmanFilter, x, u, t) = kf.A*x .+ kf.B*u .+ rand(MvNormal(kf.R1))
sample_state(pf::ParticleFilter, x, u, t) = pf.dynamics(x,u,t) + rand(pf.dynamics_density)
sample_state(pf::AdvancedParticleFilter, x, u, t) = pf.dynamics(x,u,t,true)
sample_measurement(kf::AbstractKalmanFilter, x, t) = kf.C*x .+ rand(MvNormal(kf.R2))
sample_measurement(pf, x, t) = pf.measurement(x, t) .+ rand(pf.measurement_density)
sample_measurement(pf::AdvancedParticleFilter, x, t) = pf.measurement(x, t)

num_particles(s::AbstractArray) = length(s)
num_particles(s::PFstate) = num_particles(s.x)
weights(s::PFstate) = s.w
particles(s::PFstate) = s.x
particletype(s::PFstate) = eltype(s.x)
particletype(kf::AbstractKalmanFilter) = typeof(kf.x)
covtype(kf::AbstractKalmanFilter) = typeof(kf.R)
index(pf::AbstractParticleFilter) = pf.state.t[]
index(f::AbstractFilter) = f.t[]
state(kf::AbstractKalmanFilter) = kf.x
covariance(kf::AbstractKalmanFilter) = kf.R

@forward ParticleFilter.state num_particles, weights, particles, particletype
@forward AdvancedParticleFilter.state num_particles, weights, particles, particletype