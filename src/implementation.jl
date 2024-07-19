module Implementation

import SysInfo: ncputhreads, ncores, nnuma, nsockets, hyperthreading_is_enabled

using PrettyTables: pretty_table
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
function getsortedby(getidx, byidx; matrix = getsystem().matrix, kwargs...)
    @views sortslices(matrix; dims = 1, by = x -> x[byidx], kwargs...)[:, getidx]
end
function getsortedby(getidx, bytuple::Tuple; matrix = getsystem().matrix, kwargs...)
    @views sortslices(matrix; dims = 1, by = x -> Tuple(x[i] for i in bytuple), kwargs...)[
        :,
        getidx,
    ]
end
ncputhreads(sys::System = getsystem()) = size(sys.matrix, 1)
ncores(sys::System = getsystem()) = maximum(@view(sys.matrix[:, ICORE]))
nnuma(sys::System = getsystem()) = maximum(@view(sys.matrix[:, INUMA]))
nsockets(sys::System = getsystem()) = maximum(@view(sys.matrix[:, ISOCKET]))
hyperthreading_is_enabled(sys::System = getsystem()) = any(>(1), @view(sys.matrix[:, ISMT]))

end
