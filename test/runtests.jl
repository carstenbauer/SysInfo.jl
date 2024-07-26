using SysInfo
using Test

const TestSystems = SysInfo.TestSystems
const IID = SysInfo.Internals.IID
const IOSID = SysInfo.Internals.IOSID
const ICORE = SysInfo.Internals.ICORE
const INUMA = SysInfo.Internals.INUMA
const ISOCKET = SysInfo.Internals.ISOCKET
const ISMT = SysInfo.Internals.ISMT
const IEFFICIENCY = SysInfo.Internals.IEFFICIENCY


function basic_tests()
    @test isnothing(sysinfo()) # exported
    @test SysInfo.ncputhreads() > 0
    @test SysInfo.ncores() > 0
    @test SysInfo.nsockets() > 0
    @test SysInfo.nnuma() > 0
    @test SysInfo.nsmt() > 0
    @test SysInfo.ncorekinds() > 0
end

function index_tests()
    for i = 1:SysInfo.ncputhreads()
        @test SysInfo.id(SysInfo.cpuid(i)) == i
    end

    @test SysInfo.ishyperthread(SysInfo.cpuid(1)) isa Bool
    @test SysInfo.cpuid_to_numanode(SysInfo.cpuid(1)) == 1
    @test SysInfo.cpuid_to_efficiency(SysInfo.cpuid(1)) == 1
    @test SysInfo.isefficiencycore(SysInfo.cpuid(1)) isa Bool

    icore = rand(1:SysInfo.ncores())
    isocket = rand(1:SysInfo.nsockets())
    inuma = rand(1:SysInfo.nnuma())
    @test SysInfo.core(icore) isa Vector{<:Integer}
    @test SysInfo.numa(inuma) isa Vector{<:Integer}
    @test length(SysInfo.numa(inuma, 1:1)) == 1
    @test SysInfo.socket(isocket) isa Vector{<:Integer}
    @test length(SysInfo.socket(isocket, 1:1)) == 1
    @test SysInfo.node() isa Vector{<:Integer}
    @test length(SysInfo.node(1:1)) == 1
    @test SysInfo.node(icore:icore; compact = true) == [SysInfo.cpuid(icore)]

    # TODO cores, sockets, numas
end

function internal_matrix_tests()
    @test @views issorted(SysInfo.stdsys().matrix[:, IID])
    @test @views issorted(SysInfo.stdsys().matrix[:, ICORE])
    @test @views issorted(SysInfo.stdsys().matrix[:, INUMA])
    @test @views issorted(SysInfo.stdsys().matrix[:, ISOCKET])
    if SysInfo.nsmt() > 1
        @test !issorted(SysInfo.stdsys().matrix[:, ISMT])
    else
        @test issorted(SysInfo.stdsys().matrix[:, ISMT])
    end
end

@testset "SysInfo.jl" begin
    @testset "HostSystem" begin
        basic_tests()
        index_tests()
        # lscpu is typically only available on linux
        @static if Sys.islinux()
            # check consistency between hwloc and lscpu backend
            @test SysInfo.Internals.check_consistency_backends()
        end
    end

    @testset "TestSystems" begin
        for name in TestSystems.list()
            println()
            @info("\nTestSystem: $name\n")
            ts = TestSystems.load(name)
            TestSystems.with_testsystem(ts) do
                basic_tests()
                index_tests()
                internal_matrix_tests()
                # check consistency between hwloc and lscpu backend (if possible)
                if TestSystems.hashwloc(ts) && TestSystems.haslscpu(ts)
                    if name in ("DiracTestbedGPUNode",)
                        # DiracTestbedGPUNode:
                        #       Order of CPU/OS IDs doesn't match. Unclear how to fix this.
                    else
                        @info("→ performing consistency check")
                        @test SysInfo.Internals.check_consistency_backends(;
                            sys_hwloc = TestSystems.testsystem2system(ts; backend = :hwloc),
                            sys_lscpu = TestSystems.testsystem2system(ts; backend = :lscpu),
                        )
                    end
                end
            end
        end
        println()
    end
end
