module Implementation

import SysInfo: ncputhreads, ncores, nnuma, nsockets, hyperthreading_is_enabled, sysinfo

using Hwloc: Hwloc, gettopology, hwloc_isa, num_virtual_cores

include("type.jl")

const sys = Ref{Union{Nothing,System}}(nothing)

function getsystem()
    if isnothing(sys[])
        sys[] = System()
    end
    return sys[]
end

function clear_cache()
    sys[] = nothing
    return
end

# querying
function getsortedby(getidx, byidx; sys = getsystem(), kwargs...)
    @views sortslices(sys.matrix; dims = 1, by = x -> x[byidx], kwargs...)[:, getidx]
end
function getsortedby(getidx, bytuple::Tuple; sys = getsystem(), kwargs...)
    @views sortslices(
        sys.matrix;
        dims = 1,
        by = x -> Tuple(x[i] for i in bytuple),
        kwargs...,
    )[
        :,
        getidx,
    ]
end
ncputhreads(; sys::System = getsystem()) = size(sys.matrix, 1)
ncores(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, ICORE]))
nnuma(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, INUMA]))
nsockets(; sys::System = getsystem()) = maximum(@view(sys.matrix[:, ISOCKET]))
hyperthreading_is_enabled(; sys::System = getsystem()) =
    any(>(1), @view(sys.matrix[:, ISMT]))

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

ngpus(; sys::System = getsystem()) = sys.ngpus

maxsmt(; sys) = maximum(@view(sys.matrix[:, ISMT]))

cpukind() = Sys.cpu_info()[1].model

function sysinfo(; sys::System = getsystem())
    println("Hostname: ", gethostname())
    println("CPU kind: ", cpukind())
    println()
    println(
        "$(ncores(; sys)) physical ($(ncputhreads(; sys)) virtual) cores distributed over $(nsockets(; sys)) CPU",
        nsockets(; sys) > 1 ? "s" : "",
    )
    if nsockets(; sys) > 1
        for socket = 1:nsockets(; sys)
            println(
                "\t → CPU ",
                socket,
                ": ",
                ncores_within_socket(socket; sys),
                " physical (",
                ncputhreads_within_socket(socket; sys),
                " virtual) cores",
            )
        end
    end
    println()
    println("NUMA domains: ", nnuma(; sys))
    if nsockets(; sys) > 1
        for socket = 1:nsockets(; sys)
            n = nnuma_within_socket(socket; sys)
            println("\t → CPU ", socket, ": ", n, " NUMA domain", n > 1 ? "s" : "")
        end
    end
    if ngpus(; sys) > 0
        println()
        println("Detected GPUs: ", ngpus(; sys))
    end
    return
end

end
