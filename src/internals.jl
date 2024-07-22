module Internals

import SysInfo: ncputhreads, ncores, nnuma, nsockets, hyperthreading_is_enabled, sysinfo

using Hwloc: Hwloc, gettopology, hwloc_isa, num_virtual_cores
using DelimitedFiles: readdlm

include("backends.jl")

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

# querying
# function getsortedby(getidx, byidx; sys = getsystem(), kwargs...)
#     @views sortslices(sys.matrix; dims = 1, by = x -> x[byidx], kwargs...)[:, getidx]
# end
# function getsortedby(getidx, bytuple::Tuple; sys = getsystem(), kwargs...)
#     @views sortslices(
#         sys.matrix;
#         dims = 1,
#         by = x -> Tuple(x[i] for i in bytuple),
#         kwargs...,
#     )[
#         :,
#         getidx,
#     ]
# end
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
function ncores_of_kind(kind::Integer; sys::System = getsystem())
    return count(r -> r[IEFFICIENCY] == kind && r[ISMT] == 1, eachrow(sys.matrix))
end

ngpus(; sys::System = getsystem()) = sys.ngpus

maxsmt(; sys) = maximum(@view(sys.matrix[:, ISMT]))

ncorekinds(; sys) = maximum(@view(sys.matrix[:, IEFFICIENCY]))

cpukind() = Sys.cpu_info()[1].model

function sysinfo(; sys::System = getsystem())
    println("Hostname: \t", gethostname())
    ncpus = nsockets(; sys)
    println("CPU(s): \t$(ncpus) x ", cpukind())
    if ncpus > 1
        println(
            "Cores: \t\t$(ncores(; sys)) physical ($(ncputhreads(; sys)) virtual) cores",
        )
        if ncorekinds(; sys) != 1
            if ncorekinds(; sys) == 2
                println(
                    "Core kinds: \t",
                    ncores_of_kind(1; sys),
                    " \"efficiency cores\", ",
                    ncores_of_kind(2; sys),
                    " \"performance cores\".",
                )
            end
        end
        println("NUMA domains: \t", nnuma(; sys))
    end
    if ngpus(; sys) > 0
        println("Detected GPUs: \t", ngpus(; sys))
    end

    println()
    for socket = 1:nsockets(; sys)
        println("∘ CPU ", socket, ": ")
        println(
            "\t→ ",
            ncores_within_socket(socket; sys),
            " physical (",
            ncputhreads_within_socket(socket; sys),
            " virtual) cores",
        )
        if ncorekinds(; sys) != 1
            if ncorekinds(; sys) == 2
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

end
