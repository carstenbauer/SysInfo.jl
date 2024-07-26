module TestSystems

using ..Internals: lscpu_string
import SysInfo
import Hwloc
import Serialization
import Dates

struct TestSystem
    name::String
    cpumodel::String
    cpullvm::String
    lscpustr::Union{Nothing,String}
    hwtopo::Union{Nothing,Hwloc.Object}
    sys::Union{Nothing,SysInfo.Internals.System}
end

hashwloc(ts::TestSystem) = !isnothing(ts.hwtopo)
haslscpu(ts::TestSystem) = !isnothing(ts.lscpustr)
hassys(ts::TestSystem) = !isnothing(ts.sys)

function Base.show(io::IO, ts::TestSystem)
    println(io, "TestSystem: ", ts.name)
    println(io, "→ lscpustr: ", !isnothing(ts.lscpustr))
    println(io, "→ hwtopo: ", !isnothing(ts.hwtopo))
    print(io, "→ sys: ", !isnothing(ts.sys))
end

const tsdir = joinpath(@__DIR__, "../testsystems")

list() = filter(x -> isdir(joinpath(tsdir, x)), readdir(tsdir))

function load(name::String; ispath = false)
    if !ispath
        if !(name in list())
            throw(ArgumentError("Invalid name. Check `list()` for valid names."))
        end
        dir = joinpath(tsdir, name)
    else
        if !isdir(name)
            throw(ArgumentError("Invalid path."))
        end
        dir = name
        name = basename(dir)
    end

    cpumodel = "unknown"
    cpullvm = "unknown"
    lscpustr = nothing
    hwtopo = nothing
    sys = nothing
    try
        info = readlines(joinpath(dir, "info.txt"))
        cpumodel = info[6]
        cpullvm = info[7]
        # ver = VersionNumber(info[1])
        # if ver < VERSION
        #     @warn(
        #         "Dumped with older Julia version ($ver). Binary files might not be processable."
        #     )
        # end
    catch
        @info("Couldn't process \"info.txt\". Moving on.")
    end
    try
        lscpustr = read(joinpath(dir, "lscpustr.txt"), String)
    catch
        @info("Couldn't process \"lscpustr.txt\". Moving on.")
    end
    try
        hwtopo = Serialization.deserialize(joinpath(dir, "hwtopo.bin"))
    catch
        @info("Couldn't process \"hwtopo.bin\". Moving on.")
    end
    try
        sys = Serialization.deserialize(joinpath(dir, "sys.bin"))
    catch
        @info("Couldn't process \"sys.bin\". Moving on.")
    end
    return TestSystem(name, cpumodel, cpullvm, lscpustr, hwtopo, sys)
end

testsystem2system(name::String; kwargs...) =
    testsystem2system(load(name; kwargs...); kwargs...)

function testsystem2system(ts::TestSystem; backend = nothing)
    if backend == :lscpu
        !haslscpu(ts) && error("Test system doesn't have lscpu string.")
        return SysInfo.Internals.getsystem(;
            backend = :lscpu,
            lscpustr = ts.lscpustr,
            ts.name,
            ts.cpumodel,
            ts.cpullvm,
        )
    elseif backend == :hwloc
        !hashwloc(ts) && error("Test system doesn't have hwtopo.")
        return SysInfo.Internals.getsystem(;
            backend = :hwloc,
            hwtopo = ts.hwtopo,
            ts.name,
            ts.cpumodel,
            ts.cpullvm,
        )
    elseif backend == :sys
        !hassys(ts) && error("Test system doesn't have sys.")
        return ts.sys
    else
        throw(ArgumentError("Invalid backend."))
    end
end

use(name::String; backend = nothing, kwargs...) = use(load(name; kwargs...); backend)

function use(ts::TestSystem; backend = nothing)
    if isnothing(backend)
        backend = if hashwloc(ts)
            :hwloc
        elseif haslscpu(ts)
            :lscpu
        else
            :sys
        end
    end
    @info("Using backend $backend.")
    SysInfo.Internals.sys[] = testsystem2system(ts; backend)
    return
end

function with_testsystem(f::F, ts::TestSystem; kwargs...) where {F}
    use(ts; kwargs...)
    try
        return f()
    finally
        reset()
    end
end

reset() = SysInfo.Internals.update_stdsys()

function dump_current_system(dirname = "sysinfo_dump")
    @info("Creating folder \"$dirname\".")
    isdir(dirname) && rm(dirname; force = true, recursive = true)
    mkdir(dirname)
    cd(dirname) do
        try
            open("info.txt", "w") do f
                write(f, string(Dates.today()), "\n")
                write(f, gethostname(), "\n")
                write(f, string(VERSION), "\n")
                write(f, string(pkgversion(SysInfo)), "\n")
                write(f, string(pkgversion(Hwloc)), "\n")
                write(f, SysInfo.Internals.default_cpumodel(), "\n")
                write(f, string(Sys.CPU_NAME), "\n")
                write(f, string(Sys.CPU_THREADS), "\n")
            end
        catch
            @info("Couldn't create \"info.txt\". Moving on.")
        end
        try
            write("lscpustr.txt", lscpu_string())
        catch
            @info("Couldn't create \"lscpustr.txt\". Moving on.")
        end
        try
            hwtopo = SysInfo.Internals.default_hwloc_topology()
            Serialization.serialize("hwtopo.bin", hwtopo)
        catch
            @info("Couldn't create \"hwtopo.bin\". Moving on.")
        end
        try
            sys = SysInfo.Internals.getsystem()
            Serialization.serialize("sys.bin", sys)
        catch
            @info("Couldn't create \"sys.bin\". Moving on.")
        end
        @info(
            "\n\nPlease make a PR to https://github.com/carstenbauer/SysInfo.jl in which you add the created folder as \"testsystems/NameOfYourSystem\".\n\nThank you very much! ❤\n\n"
        )
    end
end

end
