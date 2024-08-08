"Number of CPU-threads"
function ncputhreads end

"Number of cores (i.e. excluding hyperthreads)"
function ncores end

"Number of NUMA nodes"
function nnuma end

"Number of CPU sockets"
function nsockets end

"Number of different kinds of cores (e.g. efficiency and performance cores)."
function ncorekinds end

"Prints an overview of the system."
function sysinfo end

"""
The number of SMT-threads in a core. If this number varies between different cores, the
maximum is returned.
"""
function nsmt end

"""
Returns the CPU IDs that belong to core `i` (logical index, starts at 1).
Set `shuffle=true` to randomize.

Optional second argument: Logical indices to select a subset of the CPU-threads.
"""
function core end

"""
Returns the CPU IDs that belong to the `i`th NUMA domain (logical index, starts at 1).
By default, an "cores before hyperthreads" ordering is used. Set `compact=true` if you want
compact ordering. Set `shuffle=true` to randomize.

Optional second argument: Logical indices to select a subset of the CPU-threads.
"""
function numa end

"""
Returns the CPU IDs that belong to the `i`th CPU/socket (logical index, starts at 1).
By default, an "cores before hyperthreads" ordering is used. Set `compact=true` if you want
compact ordering. Set `shuffle=true` to randomize.

Optional second argument: Logical indices to select a subset of the CPU-threads.
"""
function socket end

"""
Returns all CPU IDs of the system/compute node (logical index, starts at 1).
By default, an "cores before hyperthreads" ordering is used. Set `compact=true` if you want
compact ordering. Set `shuffle=true` to randomize.

Optional argument: Logical indices to select a subset of the CPU-threads.
"""
function node end

"""
Returns the CPU IDs of the system as obtained by a round-robin scattering
between sockets. By default, within each socket, a round-robin ordering among CPU cores is
used ("cores before hyperthreads"). Provide `compact=true` to get compact ordering within
each socket. Set `shuffle=true` to randomize.

Optional first argument: Logical indices to select a subset of the sockets.
"""
function sockets end

"""
Returns the CPU IDs of the system as obtained by a round-robin scattering
between NUMA domains. Within each NUMA domain, a round-robin ordering among
CPU cores is used ("cores before hyperthreads"). Provide `compact=true` to get compact ordering
within each NUMA domain. Set `shuffle=true` to randomize.

Optional first argument: Logical indices to select a subset of the sockets.
"""
function numas end

"""
Returns the CPU IDs of the system as obtained by a round-robin scattering
between CPU cores. This is the same as `nodes(; compact=false)`.
Set `shuffle=true` to randomize.

Optional first argument: Logical indices to select a subset of the sockets.
"""
function cores end

"""
Returns the logical index (starts at 1) that corresponds to the given
CPU ID ("physical" OS index).
"""
function id end

"""
Returns the CPU ID ("physical" OS index) that corresponds to the given
logical index (starts at 1).
"""
function cpuid end

"Check whether hyperthreading is enabled."
function hyperthreading_is_enabled end

"""
Check whether the given CPU-thread is a SMT-thread / "hyperthread" (i.e. it is not the
first CPU-thread in the CPU-core).
"""
function ishyperthread end

"""
Returns the logical index (starting at 1) of the NUMA node corresponding to the given
CPU ID (CPU-thread).
"""
function cpuid_to_numanode end

"""
Returns the efficiency value of the CPU-thread with the given CPU ID.

The lowest possible value is 1. Higher values indicate less efficient cores.
On systems with only a single core kind, all cores will have value 1.
"""
function cpuid_to_efficiency end

"""
Returns true if the given CPU-thread lies inside of a CPU-core that has the highest power
efficiency of all the CPU-cores (i.e. an efficiency value of 1). If
there is only a single CPU-core kind, the return value is false for all CPU IDs.
"""
function isefficiencycore end


"""
    ncputhreads_of_core(core::Integer)

Returns the number of CPU-threads inside of the given `core`.
"""
function ncputhreads_of_core end

"""
    ncputhreads_of_numa(numa::Integer)

Returns the number of CPU-threads inside of the given `numa` domain.
"""
function ncputhreads_of_numa end

"""
    ncputhreads_of_socket(socket::Integer)

Returns the number of CPU-threads the belong to the given `socket`/CPU.
"""
function ncputhreads_of_socket end

"""
    ncores_of_numa(numa::Integer)

Returns the number of CPU-cores the belong to the given `numa` domain.
"""
function ncores_of_numa end

"""
    ncores_of_socket(socket::Integer)

Returns the number of CPU-cores the belong to the given `socket`/CPU.
"""
function ncores_of_socket end

"""
    nnuma_of_socket(socket::Integer)

Returns the number of NUMA domains the belong to the given `socket`/CPU.
"""
function nnuma_of_socket end

"""
    nsockets_of_numa(numa::Integer)

Returns the number of CPU sockets that have access to the given NUMA domain.
If the returned value is > 1, the NUMA domain is shared.
"""
function nsockets_of_numa end

"""
    ncores_of_kind(kind::Integer)

Returns the number of CPU-cores that are of the given `kind` (efficiency).
"""
function ncores_of_kind end

"""
    sockets_of_numa(numa::Integer)

Returns the logical IDs of the CPU sockets that have access to the given NUMA domain.
"""
function sockets_of_numa end

"""
    numa_of_socket(socket::Integer)

Returns the logical IDs of the NUMA domains that the given CPU socket has access to.
"""
function numa_of_socket end
