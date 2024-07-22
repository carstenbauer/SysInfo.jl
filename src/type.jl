struct System
    # Columns of the sysinfo matrix (in that order):
    #   * ID (logical, i.e. starts at 1, compact order)
    #   * OSID ("physical", i.e. starts at 0)
    #   * CORE (logical, i.e. starts at 1)
    #   * NUMA (logical, i.e. starts at 1)
    #   * SOCKET (logical, i.e. starts at 1)
    #   * SMT (logical, i.e. starts at 1): order of SMT threads within their respective core
    matrix::Matrix{Int}
    ngpus::Int
end

# helper indices for indexing into the system matrix
const IID = 1
const IOSID = 2
const ICORE = 3
const INUMA = 4
const ISOCKET = 5
const ISMT = 6

# default to hwloc backend
System() = System(Hwloc.gettopology())

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
    ngpus = 0
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
        # try detect number of GPUs
        if hwloc_isa(obj, :PCI_Device) &&
           Hwloc.hwloc_pci_class_string(obj.attr.class_id) == "3D"
            ngpus += 1
        end
    end
    return System(matrix, ngpus)
end

# pretty printing
# function Base.show(io::IO, sys::System)
#     println(io, summary(sys))
#     pretty_table(io, sys.matrix; header = [:ID, :OSID, :CORE, :NUMA, :SOCKET, :SMT])
# end


# lscpu backend
function lscpu_string()
    try
        return read(`lscpu --all --extended`, String)
    catch err
        error("Couldn't gather system information via `lscpu` (might not be available?).")
    end
end

_lscpu2table(lscpustr = nothing)::Union{Nothing,Matrix{String}} =
    readdlm(IOBuffer(lscpustr), String)

function _lscpu_table_to_columns(
    table,
)::NamedTuple{(:idcs, :cpuid, :socket, :numa, :core),NTuple{5,Vector{Int}}}
    colid_cpu = @views findfirst(isequal("CPU"), table[1, :])
    colid_socket = @views findfirst(isequal("SOCKET"), table[1, :])
    colid_numa = @views findfirst(isequal("NODE"), table[1, :])
    colid_core = @views findfirst(isequal("CORE"), table[1, :])
    colid_online = @views findfirst(isequal("ONLINE"), table[1, :])

    # only consider online cpus
    online_cpu_tblidcs = @views findall(
        x -> !(isequal(x, "no") || isequal(x, "ONLINE")),
        table[:, colid_online],
    )
    if length(online_cpu_tblidcs) != Sys.CPU_THREADS
        @warn(
            "Number of online CPUs ($(length(online_cpu_tblidcs))) doesn't match " *
            "Sys.CPU_THREADS ($(Sys.CPU_THREADS))."
        )
    end

    col_cpuid = @views parse.(Int, table[online_cpu_tblidcs, colid_cpu])
    col_socket = if isnothing(colid_socket)
        fill(zero(Int), length(online_cpu_tblidcs))
    else
        @views parse.(Int, table[online_cpu_tblidcs, colid_socket])
    end
    col_numa = if isnothing(colid_numa)
        fill(zero(Int), length(online_cpu_tblidcs))
    else
        @views parse.(Int, table[online_cpu_tblidcs, colid_numa])
    end
    col_core = @views parse.(Int, table[online_cpu_tblidcs, colid_core])
    idcs = 1:length(online_cpu_tblidcs)

    @assert length(idcs) ==
            length(col_cpuid) ==
            length(col_socket) ==
            length(col_numa) ==
            length(col_core)
    return (
        idcs = idcs,
        cpuid = col_cpuid,
        socket = col_socket,
        numa = col_numa,
        core = col_core,
    )
end

function System(lscpu_string::AbstractString)
    table = _lscpu2table(lscpu_string)
    cols = _lscpu_table_to_columns(table)

    cpuids = cols.cpuid
    @assert issorted(cols.cpuid)
    @assert length(Set(cols.cpuid)) == length(cols.cpuid) # no duplicates

    ncputhreads = length(cols.cpuid)
    ncores = length(unique(cols.core))
    # nsockets = length(unique(cols.socket))
    # count number of numa nodes
    # nnuma = length(unique(cols.numa))

    # sysinfo matrix
    coreids = unique(cols.core)
    numaids = unique(cols.numa)
    socketids = unique(cols.socket)
    # TODO cols might not be sorted?!
    coremap = Dict{Int, Int}(n => i for (i, n) in enumerate(coreids))
    numamap = Dict{Int, Int}(n => i for (i, n) in enumerate(numaids))
    socketmap = Dict{Int, Int}(n => i for (i, n) in enumerate(socketids))

    matrix = hcat(1:ncputhreads, cols.cpuid, [coremap[c] for c in cols.core],
                  [numamap[n] for n in cols.numa],
                  [socketmap[s] for s in cols.socket],
                  zeros(Int64, ncputhreads))

    matrix = sortslices(matrix; dims=1, by = x->x[3]) # goal: same logical indices as for hwloc

    # enumerate hyperthreads
    counters = ones(Int, ncores)
    @views coreordering = sortperm(matrix[:, ICORE])
    @views for i in eachindex(coreordering)
        row = coreordering[i]
        core = matrix[row, ICORE]
        matrix[row, ISMT] = counters[core]
        counters[core] += 1
    end
    return System(matrix, -1)
end
