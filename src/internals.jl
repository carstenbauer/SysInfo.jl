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
ngpus(; sys::System = stdsys()) = sys.ngpus

function cpuids(; sys::System = stdsys(), compact = false, idcs = Colon())
    mat = compact ? sys.matrix : sys.matrix_noncompact
    return @view(mat[idcs, IOSID])
end
function cpuids_of_core(coreid::Integer; sys::System = stdsys(), idcs = Colon())
    nsmt = SysInfo.nsmt(; sys)
    res = Vector{Int}(undef, nsmt)
    i = 1
    iwrite = 1
    for r in eachrow(sys.matrix)
        if r[ICORE] == coreid
            if typeof(idcs) == Colon || i in idcs
                res[iwrite] = r[IOSID]
                iwrite += 1
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
    iwrite = 1
    for r in eachrow(mat)
        if r[xid] == id
            if typeof(idcs) == Colon || i in idcs
                res[iwrite] = r[IOSID]
                iwrite += 1
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

function cpuid_to_smt(cpuid::Integer; sys::System = stdsys())
    id = SysInfo.id(cpuid)
    isnothing(id) && throw(ArgumentError("Invalid CPU ID."))
    return sys.matrix[id, ISMT]
end
function cpuid_to_core(cpuid::Integer; sys::System = stdsys())
    id = SysInfo.id(cpuid)
    isnothing(id) && throw(ArgumentError("Invalid CPU ID."))
    return sys.matrix[id, ICORE]
end
function cpuid_to_socket(cpuid::Integer; sys::System = stdsys())
    id = SysInfo.id(cpuid)
    isnothing(id) && throw(ArgumentError("Invalid CPU ID."))
    return sys.matrix[id, ISOCKET]
end

function is_last_hyperthread_in_core(cpuid::Integer; sys::System = stdsys())
    core = cpuid_to_core(cpuid; sys)
    maxsmt = SysInfo.ncputhreads_of_core(core; sys)
    mysmt = cpuid_to_smt(cpuid)
    return mysmt == maxsmt
end

"""
# Examples
```julia
roundrobin_equal_length([1,2,3,4], [5,6,7,8]) == [1,5,2,6,3,7,4,8]
```
```julia
roundrobin_equal_length(1:4, 5:8, 9:12) == [1, 5, 9, 2, 6, 10, 3, 7, 11, 4, 8, 12]
```
"""
function roundrobin_equal_length(arrays::AbstractVector...)
    # check input args
    narrays = length(arrays)
    narrays > 0 || throw(ArgumentError("No input arguments provided."))
    len = length(first(arrays))
    for a in arrays
        length(a) == len || throw(ArgumentError("Only same length inputs supported."))
    end
    # roundrobin
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

"""
# Examples
```julia
roundrobin([1,2,3,4], [5,6,7,8]) == [1,5,2,6,3,7,4,8]
```
```julia
roundrobin([1,2], [3,4,5], [6,7,8,9]) == [1, 3, 6, 2, 4, 7, 5, 8, 9]
```
"""
function roundrobin(arrays::AbstractVector...)
    # check input args
    narrays = length(arrays)
    narrays > 0 || throw(ArgumentError("No input arguments provided."))
    len = length(first(arrays))
    # are arrays of equal length?
    all_equal_length = true
    for a in arrays
        if length(a) != len
            all_equal_length = false
            break
        end
    end
    # decide what to do
    if all_equal_length
        return roundrobin_equal_length(arrays...)
    else
        common_length, iarray_min = findmin(length, arrays)
        # all arrays
        part1 = roundrobin_equal_length((@view(a[1:common_length]) for a in arrays)...)
        # remaining arrays
        arrays_new = (a for (i, a) in enumerate(arrays) if i != iarray_min)
        part2 = roundrobin((@view(a[common_length+1:end]) for a in arrays_new)...)
        return vcat(part1, part2)
    end
end

# API functions
SysInfo.ncputhreads(; sys::System = stdsys()) = size(sys.matrix, 1)
SysInfo.ncores(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, ICORE]))
SysInfo.nnuma(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, INUMA]))
SysInfo.nsockets(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, ISOCKET]))
SysInfo.ncorekinds(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, IEFFICIENCY]))
SysInfo.nsmt(; sys::System = stdsys()) = maximum(@view(sys.matrix[:, ISMT]))
function SysInfo.ncputhreads_of_core(core::Integer; sys::System = stdsys())
    return count(r -> r[ICORE] == core, eachrow(sys.matrix))
end
function SysInfo.ncputhreads_of_numa(numa::Integer; sys::System = stdsys())
    return count(r -> r[INUMA] == numa, eachrow(sys.matrix))
end
function SysInfo.ncputhreads_of_socket(socket::Integer; sys::System = stdsys())
    return count(r -> r[ISOCKET] == socket, eachrow(sys.matrix))
end
function SysInfo.ncores_of_numa(numa::Integer; sys::System = stdsys())
    return count(r -> r[INUMA] == numa && r[ISMT] == 1, eachrow(sys.matrix))
end
function SysInfo.ncores_of_socket(socket::Integer; sys::System = stdsys())
    return count(r -> r[ISOCKET] == socket && r[ISMT] == 1, eachrow(sys.matrix))
end
function SysInfo.nnuma_of_socket(socket::Integer; sys::System = stdsys())
    # OPT: Perf improve?
    return length(
        unique(
            r -> r[INUMA],
            Iterators.filter(r -> r[ISOCKET] == socket, eachrow(sys.matrix)),
        ),
    )
end
function SysInfo.nsockets_of_numa(numa::Integer; sys::System = stdsys())
    # OPT: Perf improve?
    return length(
        unique(
            r -> r[ISOCKET],
            Iterators.filter(r -> r[INUMA] == numa, eachrow(sys.matrix)),
        ),
    )
end
function SysInfo.sockets_of_numa(numa::Integer; sys::System = stdsys())
    # OPT: Perf improve?
    sockets_of_numa = Int[]
    for row in Iterators.filter(r -> r[INUMA] == numa, eachrow(sys.matrix))
        socket = row[ISOCKET]
        if !(socket in sockets_of_numa)
            push!(sockets_of_numa, socket)
        end
    end
    return sockets_of_numa
end
function SysInfo.numa_of_socket(socket::Integer; sys::System = stdsys())
    # OPT: Perf improve?
    numa_of_socket = Int[]
    for row in Iterators.filter(r -> r[ISOCKET] == socket, eachrow(sys.matrix))
        numa = row[INUMA]
        if !(numa in numa_of_socket)
            push!(numa_of_socket, numa)
        end
    end
    return numa_of_socket
end
function SysInfo.ncores_of_kind(kind::Integer; sys::System = stdsys())
    return count(r -> r[IEFFICIENCY] == kind && r[ISMT] == 1, eachrow(sys.matrix))
end
SysInfo.hyperthreading_is_enabled(; sys::System = stdsys()) =
    any(>(1), @view(sys.matrix[:, ISMT]))
function SysInfo.id(cpuid::Integer; sys::System = stdsys())
    idx = findfirst(==(cpuid), @view(sys.matrix[:, IOSID]))
    isnothing(idx) && return
    return sys.matrix[idx, IID]
end
function SysInfo.cpuid(id::Integer; sys::System = stdsys())
    idx = findfirst(==(id), @view(sys.matrix[:, IID]))
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


function SysInfo.sysinfo(; sys::System = stdsys(), gpu = true)
    _print_sysinfo_header(; sys)

    println()
    nsmt = SysInfo.nsmt(; sys)
    for socket = 1:SysInfo.nsockets(; sys)
        println("∘ CPU ", socket, ": ")
        println(
            "\t→ ",
            SysInfo.ncores_of_socket(socket; sys),
            " cores (",
            SysInfo.ncputhreads_of_socket(socket; sys),
            " CPU-threads",
            nsmt == 1 ? "" : " due to $(nsmt)-way SMT",
            ")",
        )
        if SysInfo.ncorekinds(; sys) != 1
            if SysInfo.ncorekinds(; sys) == 2
                println(
                    "\t→ ",
                    SysInfo.ncores_of_kind(1; sys),
                    " \"efficiency cores\", ",
                    SysInfo.ncores_of_kind(2; sys),
                    " \"performance cores\".",
                )
            end
        end
        numas = SysInfo.numa_of_socket(socket; sys)
        n = length(numas)
        sockets_of_numa = SysInfo.sockets_of_numa.(numas; sys)
        print("\t→ ", n, " NUMA domain", n > 1 ? "s" : "")
        if any(x -> length(x) != 1, sockets_of_numa)
            # at least one NUMA is shared
            if n == 1
                socketids = only(sockets_of_numa)
                print(
                    " (shared with CPU",
                    length(socketids) == 2 ? "" : "s:",
                    " ",
                    join((i for i in socketids if i != socket), ','),
                    ")",
                )
            else
                print(" (some of them are shared with other CPUs)")
            end
        end
        println()
    end

    if gpu && ngpus(; sys) > 0
        println("\nDetected GPUs: \t", ngpus(; sys))
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
    nsmt = SysInfo.nsmt(; sys)
    println(io, "CPU(s): \t$(ncpus) x ", sys.cpumodel)
    println(io, "CPU target: \t", sys.cpullvm)
    if always_show_total || ncpus > 1
        println(
            io,
            "Cores: \t\t$(SysInfo.ncores(; sys))",
            " (",
            SysInfo.ncputhreads(; sys),
            " CPU-threads",
            nsmt == 1 ? "" : " due to $(nsmt)-way SMT",
            ")",
        )
        if SysInfo.ncorekinds(; sys) != 1
            if SysInfo.ncorekinds(; sys) == 2
                println(
                    io,
                    "Core kinds: \t",
                    SysInfo.ncores_of_kind(1; sys),
                    " \"efficiency cores\", ",
                    SysInfo.ncores_of_kind(2; sys),
                    " \"performance cores\".",
                )
            end
        end
        nnuma = SysInfo.nnuma(; sys)
        ncoresfirstnuma = SysInfo.ncores_of_numa(1; sys)
        print(io, "NUMA domains: \t", nnuma)
        if all(n -> SysInfo.ncores_of_numa(n; sys) == ncoresfirstnuma, 1:nnuma)
            print(" (", ncoresfirstnuma, " cores each)")
        end
        println()
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
    cpuids = collect(SysInfo.cpuids(; idcs, kwargs...))
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
    cpuids = roundrobin(cpuids_sockets...)
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
    cpuids = roundrobin(cpuids_numas...)
    shuffle && Random.shuffle!(cpuids)
    return cpuids
end

end
