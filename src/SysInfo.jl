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
        Internals.clear_cache()
    end
end

end
