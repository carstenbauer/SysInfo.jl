module Internals

import SysInfo: SysInfo
using Hwloc: Hwloc, gettopology, hwloc_isa, num_virtual_cores
using DelimitedFiles: readdlm
using Random: Random

# System type + hwloc and lscpu backends
include("backends.jl")

# global storage + accessor + clear
const sys = Ref{Union{Nothing,System}}(nothing)

function getsystem(; reload = false, backend = nothing) # default backend
    if isnothing(sys[]) || reload
        if backend == :hwloc
            sys[] = System(Hwloc.gettopology())
        elseif backend == :lscpu
            sys[] = System(lscpu_string())
        else
            sys[] = System()
        end
    end
    return sys[]
end
function clear_cache()
    sys[] = nothing
    return
end

# internal helpers
function ncores_within_socket(socket::Integer; sys::System = getsystem())
    return count(r -> r[ISOCKET] == socket && r[ISMT] == 1, eachrow(sys.matrix))
end
function ncputhreads_within_socket(socket::Integer; sys::System = getsystem())
    return count(r -> r[ISOCKET] == socket, eachrow(sys.matrix))
end
function nnuma_within_socket(socket::Integer; sys::System = getsystem())
    # OPT: Perf improve?
    return length(
        unique(
            r -> r[INUMA],
            Iterators.filter(r -> r[ISOCKET] == socket, eachrow(sys.matrix)),
        ),
    )
end
function ncores_of_kind(kind::Integer; sys::System = getsystem())
    return count(r -> r[IEFFICIENCY] == kind && r[ISMT] == 1, eachrow(sys.matrix))
end

ngpus(; sys::System = getsystem()) = sys.ngpus

function cpuids_all(; sys::System = getsystem(), compact = false, idcs = Colon())
    mat = compact ? sys.matrix : sys.matrix_noncompact
    return @view(mat[idcs, IOSID])
end
function cpuids_of_core(coreid::Integer; sys::System = getsystem(), idcs = Colon())
    nsmt = SysInfo.maxsmt(; sys)
    res = Vector{Int}(undef, nsmt)
    i = 1
    for r in eachrow(sys.matrix)
        if r[ICORE] == coreid
            if typeof(idcs) == Colon || i in idcs
                res[i] = r[IOSID]
            end
            i += 1
        end
        if i > nsmt
            break
        end
    end
    if typeof(idcs) != Colon && length(idcs) > i - 1
        throw(ArgumentError("Indices are out of bounds."))
    end
    cutoff = typeof(idcs) == Colon ? (i - 1) : min(length(idcs), i - 1)
    if cutoff < nsmt
        resize!(res, cutoff)
    end
    return res
end
function _cpuids_of_X(
    id::Integer,
    xid::Integer;
    sys::System = getsystem(),
    compact = false,
    idcs = Colon(),
)
    mat = compact ? sys.matrix : sys.matrix_noncompact
    ncputhreads = SysInfo.ncputhreads(; sys)
    breakidx = typeof(idcs) == Colon ? ncputhreads : maximum(idcs)
    res = Vector{Int}(undef, ncputhreads)
    i = 1
    for r in eachrow(mat)
        if r[xid] == id
            if typeof(idcs) == Colon || i in idcs
                res[i] = r[IOSID]
            end
            i += 1
            if i > breakidx
                break
            end
        end
    end
    if typeof(idcs) != Colon && length(idcs) > i - 1
        throw(ArgumentError("Indices are out of bounds."))
    end
    cutoff = typeof(idcs) == Colon ? (i - 1) : min(length(idcs), i - 1)
    if cutoff < ncputhreads
        resize!(res, cutoff)
    end
    return res
end
cpuids_of_socket(socketid::Integer; kwargs...) = _cpuids_of_X(socketid, ISOCKET; kwargs...)
cpuids_of_numa(numaid::Integer; kwargs...) = _cpuids_of_X(numaid, INUMA; kwargs...)

"""
# Examples
```julia
interweave([1,2,3,4], [5,6,7,8]) == [1,5,2,6,3,7,4,8]
```
```julia
interweave(1:4, 5:8, 9:12) == [1, 5, 9, 2, 6, 10, 3, 7, 11, 4, 8, 12]
```
"""
function interweave(arrays::AbstractVector...)
    # check input args
    narrays = length(arrays)
    narrays > 0 || throw(ArgumentError("No input arguments provided."))
    len = length(first(arrays))
    for a in arrays
        length(a) == len || throw(ArgumentError("Only same length inputs supported."))
    end
    # interweave
    res = zeros(eltype(first(arrays)), len * narrays)
    c = 1
    for i in eachindex(first(arrays))
        for a in arrays
            @inbounds res[c] = a[i]
            c += 1
        end
    end
    return res
end

# API functions
SysInfo.ncputhreads(; sys::System = getsystem()) = size(sys.matrix, 1)
SysInfo.ncores(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, ICORE]))
SysInfo.nnuma(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, INUMA]))
SysInfo.nsockets(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, ISOCKET]))
SysInfo.ncorekinds(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, IEFFICIENCY]))
SysInfo.maxsmt(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, ISMT]))
SysInfo.hyperthreading_is_enabled(; sys::System = getsystem()) =
    any(>(1), @view(sys.matrix[:, ISMT]))
SysInfo.id(cpuid::Integer; sys::System = getsystem()) =
    findfirst(==(cpuid), @view(sys.matrix[:, IOSID]))
function SysInfo.cpuid(cpuid::Integer; sys::System = getsystem())
    idx = findfirst(==(cpuid), @view(sys.matrix[:, IID]))
    isnothing(idx) && return
    return sys.matrix[idx, IOSID]
end


function SysInfo.sysinfo(; sys::System = getsystem())
    cpukind = () -> Sys.cpu_info()[1].model

    println("Hostname: \t", gethostname())
    ncpus = SysInfo.nsockets(; sys)
    println("CPU(s): \t$(ncpus) x ", cpukind())
    if ncpus > 1
        println(
            "Cores: \t\t$(SysInfo.ncores(; sys)) physical ($(SysInfo.ncputhreads(; sys)) virtual) cores",
        )
        if SysInfo.ncorekinds(; sys) != 1
            if SysInfo.ncorekinds(; sys) == 2
                println(
                    "Core kinds: \t",
                    ncores_of_kind(1; sys),
                    " \"efficiency cores\", ",
                    ncores_of_kind(2; sys),
                    " \"performance cores\".",
                )
            end
        end
        println("NUMA domains: \t", SysInfo.nnuma(; sys))
    end
    if ngpus(; sys) > 0
        println("Detected GPUs: \t", ngpus(; sys))
    end

    println()
    for socket = 1:SysInfo.nsockets(; sys)
        println("∘ CPU ", socket, ": ")
        println(
            "\t→ ",
            ncores_within_socket(socket; sys),
            " physical (",
            ncputhreads_within_socket(socket; sys),
            " virtual) cores",
        )
        if SysInfo.ncorekinds(; sys) != 1
            if SysInfo.ncorekinds(; sys) == 2
                println(
                    "\t→ ",
                    ncores_of_kind(1; sys),
                    " \"efficiency cores\", ",
                    ncores_of_kind(2; sys),
                    " \"performance cores\".",
                )
            end
        end
        n = nnuma_within_socket(socket; sys)
        println("\t→ ", n, " NUMA domain", n > 1 ? "s" : "")
    end
    return
end

# High-level API for accessing cpuids
const T_idcs = Union{Colon,AbstractVector{<:Integer},Integer}

function SysInfo.core(i::Integer, idcs::T_idcs = Colon(); shuffle = false, kwargs...)
    idcs = idcs isa Integer ? [idcs] : idcs
    cpuids = cpuids_of_core(i; idcs, kwargs...)
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end
function SysInfo.numa(i::Integer, idcs::T_idcs = Colon(); shuffle = false, kwargs...)
    idcs = idcs isa Integer ? [idcs] : idcs
    cpuids = cpuids_of_numa(i; idcs, kwargs...)
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end
function SysInfo.socket(i::Integer, idcs::T_idcs = Colon(); shuffle = false, kwargs...)
    idcs = idcs isa Integer ? [idcs] : idcs
    cpuids = cpuids_of_socket(i; idcs, kwargs...)
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end
function SysInfo.node(idcs::T_idcs = Colon(); shuffle = false, kwargs...)
    idcs = idcs isa Integer ? [idcs] : idcs
    cpuids = collect(cpuids_all(; idcs, kwargs...))
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end

function SysInfo.cores(args...; compact = false, kwargs...)
    return SysInfo.node(args...; kwargs..., compact)
end
function SysInfo.sockets(
    idcs::Union{Colon,AbstractVector{<:Integer}} = Colon();
    shuffle = false,
    kwargs...,
)
    sockets = typeof(idcs) == Colon ? (1:SysInfo.nsockets()) : idcs
    cpuids_sockets = [cpuids_of_socket(s; kwargs...) for s in sockets]
    cpuids = interweave(cpuids_sockets...)
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end
function SysInfo.numas(
    idcs::Union{Colon,AbstractVector{<:Integer}} = Colon();
    shuffle = false,
    kwargs...,
)
    numas = typeof(idcs) == Colon ? (1:SysInfo.nnuma()) : idcs
    cpuids_numas = [cpuids_of_numa(s; kwargs...) for s in numas]
    cpuids = interweave(cpuids_numas...)
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end

end
