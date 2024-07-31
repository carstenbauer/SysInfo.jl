module SysInfo

include("public_macro.jl")
include("api.jl")
include("internals.jl")
include("testsystems.jl")

import .Internals: Internals, cpuids, getsystem, stdsys

# public API
export sysinfo
@public ncputhreads, ncores, nsockets, nnuma, ncorekinds
@public hyperthreading_is_enabled, ishyperthread, isefficiencycore
@public core, numa, socket, node, cores, sockets, numas
@public id, cpuid, cpuid_to_numanode, cpuid_to_efficiency
@public ncputhreads_within_core, ncputhreads_within_numa, ncputhreads_within_socket
@public ncores_within_numa, ncores_within_socket
@public nnuma_within_socket
@public ncores_of_kind

# precompile
import PrecompileTools
PrecompileTools.@compile_workload begin
    redirect_stdout(Base.DevNull()) do
        sysinfo()
        ncputhreads()
        ncores()
        nsockets()
        nnuma()
        ncorekinds()
        hyperthreading_is_enabled()
        ishyperthread(0)
        isefficiencycore(0)
        core(1)
        numa(1)
        socket(1)
        node(1)
        cores(1:1)
        sockets(1:1)
        numas(1:1)
        id(0)
        cpuid(1)
        cpuid_to_numanode(0)
        cpuid_to_efficiency(0)
        ncputhreads_within_core(1)
        ncputhreads_within_numa(1)
        ncputhreads_within_socket(1)
        ncores_within_numa(1)
        ncores_within_socket(1)
        nnuma_within_socket(1)
        ncores_of_kind(1)
        Internals.clear_cache()
    end
end

end
