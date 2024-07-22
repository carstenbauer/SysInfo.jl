module SysInfo

include("api.jl")
include("implementation.jl")

export ncputhreads, ncores, nsockets, nnuma, hyperthreading_is_enabled, sysinfo

import .Implementation: clear_cache

# precompile
import PrecompileTools
PrecompileTools.@compile_workload begin
    redirect_stdout(Base.DevNull()) do
        sysinfo()
    end
    clear_cache()
end

end
