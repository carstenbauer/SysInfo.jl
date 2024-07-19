struct System
    # Columns of the sysinfo matrix (in that order):
    #   * ID (logical, i.e. starts at 1)
    #   * OSID ("physical", i.e. starts at 0)
    #   * CORE (logical, i.e. starts at 1)
    #   * NUMA (logical, i.e. starts at 1)
    #   * SOCKET (logical, i.e. starts at 1)
    #   * SMT (logical, i.e. starts at 1): order of SMT threads within their respective core
    matrix::Matrix{Int}
end

# helper indices for indexing into the system matrix
const IID = 1
const IOSID = 2
const ICORE = 3
const INUMA = 4
const ISOCKET = 5
const ISMT = 6

# default to hwloc backend
System() = System(Hwloc.gettopology(; io = false))

# hwloc backend
function System(topo::Hwloc.Object)
    if !hwloc_isa(topo, :Machine)
        throw(
            ArgumentError(
                "Can only construct a System object from a Machine object (the root of the Hwloc tree).",
            ),
        )
    end

    local isocket
    local icore
    local ismt
    local id
    local osid
    inuma = 0
    row = 1
    matrix = fill(-1, (num_virtual_cores(), 6))
    for obj in topo
        hwloc_isa(obj, :Package) && (isocket = obj.logical_index + 1)
        hwloc_isa(obj, :NUMANode) && (inuma += 1)
        if hwloc_isa(obj, :Core)
            icore = obj.logical_index + 1
            ismt = 1
        end
        if hwloc_isa(obj, :PU)
            id = obj.logical_index + 1
            osid = obj.os_index
            matrix[row, IID] = id
            matrix[row, IOSID] = osid
            matrix[row, ICORE] = icore
            matrix[row, INUMA] = inuma
            matrix[row, ISOCKET] = isocket
            matrix[row, ISMT] = ismt
            row += 1
            ismt += 1
        end
    end
    # @assert @view(matrix[:, 1]) == 1:num_virtual_cores()
    return System(matrix)
end

# querying
ncputhreads(sys::System) = size(sys.matrix, 1)
ncores(sys::System) = maximum(@view(sys.matrix[:, ICORE]))
nnuma(sys::System) = maximum(@view(sys.matrix[:, INUMA]))
nsockets(sys::System) = maximum(@view(sys.matrix[:, ISOCKET]))

# pretty printing
function Base.show(io::IO, sys::System)
    println(io, summary(sys))
    pretty_table(io, sys.matrix; header = [:ID, :OSID, :CORE, :NUMA, :SOCKET, :SMT])
end
