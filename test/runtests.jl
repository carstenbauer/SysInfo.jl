using SysInfo
using Test

@testset "SysInfo.jl" begin
    @test SysInfo.ncputhreads() > 0    # Write your tests here.
    @test SysInfo.ncores() > 0    # Write your tests here.
    @test SysInfo.nsockets() > 0    # Write your tests here.
    @test SysInfo.nnuma() > 0    # Write your tests here.
    @test SysInfo.maxsmt() > 0
    @test SysInfo.ncorekinds() > 0
    @test SysInfo.id(0) == 1

    @test isnothing(sysinfo()) # exported

    @static if Sys.islinux()
        @test SysInfo.Internals.check_consistency_backends()
    end

    # TODO test core, socket, numa, node, cores, sockets, numas
end
