using SysInfo
using Test

@testset "SysInfo.jl" begin
    @test ncputhreads() > 0    # Write your tests here.
    @test ncores() > 0    # Write your tests here.
    @test nsockets() > 0    # Write your tests here.
    @test nnuma() > 0    # Write your tests here.
    @test isnothing(sysinfo())
end
