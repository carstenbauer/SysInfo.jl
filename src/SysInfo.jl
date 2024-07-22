module SysInfo

include("utils.jl")
include("api.jl")
include("implementation.jl")

import .Implementation: clear_cache

# public API
export sysinfo
@public ncputhreads, ncores, nsockets, nnuma, hyperthreading_is_enabled

# precompile
import PrecompileTools
PrecompileTools.@compile_workload begin
    redirect_stdout(Base.DevNull()) do
        sysinfo()
    end
    clear_cache()
end

end
