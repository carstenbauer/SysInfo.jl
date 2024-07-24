module SysInfo

include("public_macro.jl")
include("api.jl")
include("internals.jl")

import .Internals: cpuids_all, getsystem

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
    end
    SysInfo.Internals.clear_cache()
end

end
