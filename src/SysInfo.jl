module SysInfo

include("api.jl")
include("implementation.jl")

export ncputhreads, ncores, nsockets, nnuma, hyperthreading_is_enabled

end
