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

Optional second argument: Logical indices to select a subset of the CPU-threads.
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
