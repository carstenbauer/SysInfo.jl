struct System
    name::String
    cpumodel::String
    cpullvm::String
    # Columns of the sysinfo matrix (in that order):
    #   * ID (logical, i.e. starts at 1, compact order)
    #   * OSID ("physical", i.e. starts at 0)
    #   * CORE (logical, i.e. starts at 1)
    #   * NUMA (logical, i.e. starts at 1)
    #   * SOCKET (logical, i.e. starts at 1)
    #   * SMT (logical, i.e. starts at 1): order of SMT threads within their respective core
    #   * EFFICIENCY RANK (logical, i.e. starts at 1): smaller values means higher efficiency (if there are different efficiency cores)
    matrix::Matrix{Int}
    matrix_noncompact::Matrix{Int} # same as matrix but sorted by ISMT (i.e. cores before hyperthreads)
    ngpus::Int
end

# helper indices for indexing into the system matrix
const IID = 1
const IOSID = 2
const ICORE = 3
const INUMA = 4
const ISOCKET = 5
const ISMT = 6
const IEFFICIENCY = 7

default_name() = gethostname()
default_cpumodel() = Sys.cpu_info()[1].model
default_cpullvm() = Sys.CPU_NAME
default_hwloc_topology() = Hwloc.gettopology(; reload = true, io = true, disallowed = true)

# default to hwloc backend
System(; kwargs...) = System(default_hwloc_topology(); kwargs...)

function getsystem(;
    backend = nothing,
    lscpustr = nothing,
    hwtopo = nothing,
    disallowed = true,
    name = default_name(),
    cpumodel = default_cpumodel(),
    cpullvm = default_cpullvm(),
)
    if backend == :hwloc
        sys = System(
            isnothing(hwtopo) ? Hwloc.gettopology(; reload = true, disallowed) : hwtopo;
            name,
            cpumodel,
            cpullvm,
        )
    elseif backend == :lscpu
        sys =
            System(isnothing(lscpustr) ? lscpu_string() : lscpustr; name, cpumodel, cpullvm)
    else
        sys = System(; name, cpumodel, cpullvm)
    end
    return sys
end

# hwloc backend
function System(topo::Hwloc.Object; name, cpumodel, cpullvm)
    if !hwloc_isa(topo, :Machine)
        throw(
            ArgumentError(
                "Can only construct a System object from a Machine object (the root of the Hwloc tree).",
            ),
        )
    end

    cks = Hwloc.get_cpukind_info() # TODO use topo arg
    has_multiple_cpu_kinds = !isempty(cks)
    local isocket
    local icore
    local ismt
    local id
    local osid
    inuma = 0
    row = 1
    ngpus = 0
    ncputhreads = count(hwloc_isa(:PU), topo)
    matrix = fill(-1, (ncputhreads, 7))
    for obj in topo
        hwloc_isa(obj, :Package) && (isocket = obj.logical_index + 1)
        hwloc_isa(obj, :NUMANode) && (inuma += 1)
        if hwloc_isa(obj, :Core)
            icore = obj.logical_index + 1
            # icore = obj.os_index
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
            if has_multiple_cpu_kinds
                matrix[row, IEFFICIENCY] = osid2cpukind(osid; cks)
            else
                matrix[row, IEFFICIENCY] = 1
            end
            row += 1
            ismt += 1
        end
        # try detect number of GPUs
        if hwloc_isa(obj, :PCI_Device) &&
           Hwloc.hwloc_pci_class_string(obj.attr.class_id) == "3D"
            ngpus += 1
        end
    end
    @assert @view(matrix[:, IID]) == 1:ncputhreads
    matrix_noncompact = sortslices(matrix; dims = 1, by = x -> x[ISMT])
    return System(name, cpumodel, cpullvm, matrix, matrix_noncompact, ngpus)
end

function _ith_in_mask(mask::Culong, i::Integer)
    # i starts at 0
    imask = Culong(0) | (1 << i)
    return !iszero(mask & imask)
end

function osid2cpukind(i; cks = Hwloc.get_cpukind_info())
    for (kind, x) in enumerate(cks)
        for (k, mask) in enumerate(x.masks)
            offset = (k - 1) * sizeof(Clong) * 8
            if _ith_in_mask(mask, i - offset)
                return kind
            end
        end
    end
    return -1
end


# lscpu backend
function lscpu_string()
    try
        return read(`lscpu --all --extended`, String)
    catch err
        error("Couldn't gather system information via `lscpu` (might not be available?).")
    end
end

function _lscpu_table_to_matrix(table)
    colid_cpu = @views findfirst(isequal("CPU"), table[1, :])
    colid_socket = @views findfirst(isequal("SOCKET"), table[1, :])
    colid_numa = @views findfirst(isequal("NODE"), table[1, :])
    colid_core = @views findfirst(isequal("CORE"), table[1, :])
    colid_online = @views findfirst(isequal("ONLINE"), table[1, :])

    # only consider online cpus
    online_cpu_tblidcs = findall(
        x -> !(isequal(x, "no") || isequal(x, "ONLINE")),
        @view(table[:, colid_online]),
    )

    # build lscpu matrix (all OS IDs)
    matrix_osids = zeros(Int, length(online_cpu_tblidcs), 4)
    for (i, row) in enumerate(eachrow(matrix_osids))
        j = online_cpu_tblidcs[i]
        row[1] = parse(Int, table[j, colid_cpu])
        row[2] = parse(Int, table[j, colid_core])
        row[3] = isnothing(colid_numa) ? 0 : parse(Int, table[j, colid_numa])
        row[4] = isnothing(colid_socket) ? 0 : parse(Int, table[j, colid_socket])
    end
    return matrix_osids
end

# lscpu backend
function System(lscpu_string::AbstractString; name, cpumodel, cpullvm)
    table = readdlm(IOBuffer(lscpu_string), String)
    matrix_osids = _lscpu_table_to_matrix(table)

    # sort the matrix (with OS IDs) similar to hwloc
    matrix_osids = getsortedby(matrix_osids, (4, 3, 2, 1))

    # define logical indices based on the order of appearance (after the sorting above)
    socketmap =
        Dict{Int,Int}(n => i for (i, n) in enumerate(unique(@view(matrix_osids[:, 4]))))
    numamap =
        Dict{Int,Int}(n => i for (i, n) in enumerate(unique(@view(matrix_osids[:, 3]))))
    coremap =
        Dict{Int,Int}(n => i for (i, n) in enumerate(unique(@view(matrix_osids[:, 2]))))

    # build sys matrix
    ncputhreads = size(matrix_osids, 1)
    matrix = hcat(
        1:ncputhreads,
        @view(matrix_osids[:, 1]),
        [coremap[c] for c in @view(matrix_osids[:, 2])],
        [numamap[c] for c in @view(matrix_osids[:, 3])],
        [socketmap[c] for c in @view(matrix_osids[:, 4])],
        zeros(Int64, ncputhreads),
        ones(Int64, ncputhreads),
    )

    # enumerate hyperthreads
    ncores = length(unique(matrix[:, ICORE]))
    # @assert sort(unique(@view(matrix[:, ICORE]))) == 1:ncores
    counts = ones(Int, ncores)
    for r in eachrow(matrix)
        r[ISMT] = counts[r[ICORE]]
        counts[r[ICORE]] += 1
    end

    matrix_noncompact = sortslices(matrix; dims = 1, by = x -> x[ISMT])
    return System(name, cpumodel, cpullvm, matrix, matrix_noncompact, -1)
end

function getsortedby(matrix, bytuple::Tuple; kwargs...)
    @views sortslices(matrix; dims = 1, by = x -> Tuple(x[i] for i in bytuple), kwargs...)
end

# consistency check
function check_consistency_backends(;
    sys_hwloc = getsystem(; backend = :hwloc),
    sys_lscpu = getsystem(; backend = :lscpu),
)
    # exclude efficiency
    mat_hwloc = sys_hwloc.matrix[:, 1:end-1]
    mat_lscpu = sys_lscpu.matrix[:, 1:end-1]
    mat_noncompact_hwloc = sys_hwloc.matrix_noncompact[:, 1:end-1]
    mat_noncompact_lscpu = sys_lscpu.matrix_noncompact[:, 1:end-1]
    # compare
    return mat_hwloc == mat_lscpu && mat_noncompact_hwloc == mat_noncompact_lscpu
end
