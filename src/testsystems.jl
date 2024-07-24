module TestSystems

using ..Internals: lscpu_string

struct TestSystem
    name::String
    lscpustr::String
    # TODO: sys object from jld2 maybe
end

const isinitialized = Ref{Bool}(false)
const testsystems = Dict{String,TestSystem}()

function initialize()
    empty!(testsystems)
    tsdir = joinpath(@__DIR__, "../testsystems")
    for name in filter(x -> isdir(joinpath(tsdir, x)), readdir(tsdir))
        try
            fname = joinpath(tsdir, name, "lscpustr.txt")
            lscpustr = read(fname, String)
            testsystems[name] = TestSystem(name, lscpustr)
        catch err
            @error("Couldn't process system \"$name\".")
        end
    end
    return
end

names() = [k for (k, v) in testsystems]

function get(name::String)
    for (k, v) in testsystems
        if k == name
            return v
        end
    end
    throw(ArgumentError("Invalid name."))
end

function dump_current_system()
    @info("Creating file \"lscpustr.txt\".")
    write("lscpustr.txt", lscpu_string())
    @info("\n\nPlease make a PR to https://github.com/carstenbauer/SysInfo.jl in which you add the created file(s) under \"testsystems/NameOfYourSystem\".\n\nThank you very much! ❤\n\n")
end

end
