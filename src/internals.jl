module Internals

import SysInfo: SysInfo
using Hwloc: Hwloc, gettopology, hwloc_isa, num_virtual_cores
using DelimitedFiles: readdlm
using Random: Random

# System type + hwloc and lscpu backends
include("backends.jl")

# global storage + accessor + clear
const sys = Ref{Union{Nothing,System}}(nothing)

function stdsys(; kwargs...)
    isnothing(sys[]) && update_stdsys(kwargs...)
    return sys[]
end
function update_stdsys(; kwargs...)
    sys[] = getsystem(; kwargs...)
    return
end
function clear_cache()
    sys[] = nothing
    return
end

# internal helpers
function ncores_within_socket(socket::Integer; sys::System = stdsys())
    return count(r -> r[ISOCKET] == socket && r[ISMT] == 1, eachrow(sys.matrix))
end
function ncputhreads_within_socket(socket::Integer; sys::System = stdsys())
    return count(r -> r[ISOCKET] == socket, eachrow(sys.matrix))
end
function nnuma_within_socket(socket::Integer; sys::System = stdsys())
    # OPT: Perf improve?
    return length(
        unique(
            r -> r[INUMA],
            Iterators.filter(r -> r[ISOCKET] == socket, eachrow(sys.matrix)),
        ),
    )
end
function ncores_of_kind(kind::Integer; sys::System = stdsys())
    return count(r -> r[IEFFICIENCY] == kind && r[ISMT] == 1, eachrow(sys.matrix))
end

ngpus(; sys::System = stdsys()) = sys.ngpus

function cpuids_all(; sys::System = stdsys(), compact = false, idcs = Colon())
    mat = compact ? sys.matrix : sys.matrix_noncompact
    return @view(mat[idcs, IOSID])
end
function cpuids_of_core(coreid::Integer; sys::System = stdsys(), idcs = Colon())
    nsmt = SysInfo.nsmt(; sys)
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
    sys::System = stdsys(),
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
SysInfo.ncputhreads(; sys::System = stdsys()) = size(sys.matrix, 1)
SysInfo.ncores(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, ICORE]))
SysInfo.nnuma(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, INUMA]))
SysInfo.nsockets(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, ISOCKET]))
SysInfo.ncorekinds(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, IEFFICIENCY]))
SysInfo.nsmt(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, ISMT]))
SysInfo.hyperthreading_is_enabled(; sys::System = stdsys()) =
    any(>(1), @view(sys.matrix[:, ISMT]))
SysInfo.id(cpuid::Integer; sys::System = stdsys()) =
    findfirst(==(cpuid), @view(sys.matrix[:, IOSID]))
function SysInfo.cpuid(cpuid::Integer; sys::System = stdsys())
    idx = findfirst(==(cpuid), @view(sys.matrix[:, IID]))
    isnothing(idx) && return
    return sys.matrix[idx, IOSID]
end
function SysInfo.ishyperthread(cpuid::Integer; sys::System = stdsys())
    id = SysInfo.id(cpuid)
    isnothing(id) && throw(ArgumentError("Invalid CPU ID."))
    return sys.matrix[id, ISMT] != 1
end
function SysInfo.cpuid_to_numanode(cpuid::Integer; sys::System = stdsys())
    id = SysInfo.id(cpuid)
    isnothing(id) && throw(ArgumentError("Invalid CPU ID."))
    return sys.matrix[id, INUMA]
end
function SysInfo.cpuid_to_efficiency(cpuid::Integer; sys::System = stdsys())
    id = SysInfo.id(cpuid)
    isnothing(id) && throw(ArgumentError("Invalid CPU ID."))
    return sys.matrix[id, IEFFICIENCY]
end
function SysInfo.isefficiencycore(cpuid::Integer; sys::System = stdsys())
    return SysInfo.ncorekinds() > 1 && SysInfo.cpuid_to_efficiency(cpuid; sys) == 1
end


function SysInfo.sysinfo(; sys::System = stdsys())
    _print_sysinfo_header(; sys)

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

function _print_sysinfo_header(;
    io = stdout,
    sys::System = stdsys(),
    gpu = true,
    always_show_total = false,
)

    println(io, "Hostname: \t", sys.name)
    ncpus = SysInfo.nsockets(; sys)
    println(io, "CPU(s): \t$(ncpus) x ", sys.cpumodel)
    if always_show_total || ncpus > 1
        println(
            io,
            "Cores: \t\t$(SysInfo.ncores(; sys)) physical ($(SysInfo.ncputhreads(; sys)) virtual) cores",
        )
        if SysInfo.ncorekinds(; sys) != 1
            if SysInfo.ncorekinds(; sys) == 2
                println(
                    io,
                    "Core kinds: \t",
                    ncores_of_kind(1; sys),
                    " \"efficiency cores\", ",
                    ncores_of_kind(2; sys),
                    " \"performance cores\".",
                )
            end
        end
        println(io, "NUMA domains: \t", SysInfo.nnuma(; sys))
    end
    if gpu && ngpus(; sys) > 0
        println("Detected GPUs: \t", ngpus(; sys))
    end
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
