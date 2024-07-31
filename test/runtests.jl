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
    @testset "basic_tests" begin
        @test isnothing(sysinfo()) # exported
        @test SysInfo.ncputhreads() isa Integer
        @test SysInfo.ncputhreads() > 0
        @test SysInfo.ncores() isa Integer
        @test SysInfo.ncores() > 0
        @test SysInfo.nsockets() isa Integer
        @test SysInfo.nsockets() > 0
        @test SysInfo.nnuma() isa Integer
        @test SysInfo.nnuma() > 0
        @test SysInfo.nsmt() isa Integer
        @test SysInfo.nsmt() > 0
        @test SysInfo.ncorekinds() isa Integer
        @test SysInfo.ncorekinds() > 0

        @test SysInfo.ncputhreads_within_core(1) isa Integer
        nsmt = SysInfo.nsmt()
        for c = 1:SysInfo.ncputhreads()
            @test SysInfo.ncputhreads_within_core(c) <= nsmt
        end

        @test SysInfo.ncputhreads_within_numa(1) isa Integer
        @test SysInfo.ncputhreads_within_numa(1) > 0
        @test SysInfo.ncputhreads_within_socket(1) isa Integer
        @test SysInfo.ncputhreads_within_socket(1) > 0
        @test SysInfo.ncores_within_numa(1) isa Integer
        @test SysInfo.ncores_within_numa(1) > 0
        @test SysInfo.ncores_within_socket(1) isa Integer
        @test SysInfo.ncores_within_socket(1) > 0

        @test SysInfo.ishyperthread(SysInfo.cpuid(1)) isa Bool
        @test SysInfo.isefficiencycore(SysInfo.cpuid(1)) isa Bool
    end
end

function _check_compactness(cpuids_notcompact, cpuids_compact)
    @test issorted(cpuids_notcompact, by = SysInfo.ishyperthread)
    # @test !issorted(SysInfo.Internals.cpuid_to_core.(cpuids_notcompact))
    if SysInfo.hyperthreading_is_enabled()
        @test !issorted(cpuids_compact, by = SysInfo.ishyperthread)
        #     @test issorted(SysInfo.Internals.cpuid_to_core.(cpuids_compact))
    end
end

function index_tests()
    @testset "index_tests" begin
        for i = 1:SysInfo.ncputhreads()
            @test SysInfo.id(SysInfo.cpuid(i)) == i
        end

        @test SysInfo.cpuid_to_numanode(SysInfo.cpuid(1)) == 1
        @test SysInfo.cpuid_to_efficiency(SysInfo.cpuid(1)) == 1

        icputhread = rand(1:SysInfo.ncputhreads())
        icore = rand(1:SysInfo.ncores())
        isocket = rand(1:SysInfo.nsockets())
        inuma = rand(1:SysInfo.nnuma())

        @test SysInfo.core(icore) isa Vector{<:Integer}
        @test SysInfo.core(icore, 1:1) isa Vector{<:Integer}
        @test length(SysInfo.core(icore, 1:1)) == 1
        for cpuid in SysInfo.core(icore)
            @test SysInfo.Internals.cpuid_to_core(cpuid) == icore
        end
        if SysInfo.ncputhreads_within_core(icore) > 1
            @test SysInfo.ishyperthread(only(SysInfo.core(icore, 2)))
        end

        @test SysInfo.socket(isocket) isa Vector{<:Integer}
        @test SysInfo.socket(isocket, 1:1) isa Vector{<:Integer}
        @test length(SysInfo.socket(isocket, 1:1)) == 1
        @test SysInfo.socket(1; compact = true) isa Vector{<:Integer}
        for cpuid in SysInfo.socket(isocket; compact = true)
            @test SysInfo.Internals.cpuid_to_socket(cpuid) == isocket
        end
        _check_compactness(
            SysInfo.socket(1; compact = false),
            SysInfo.socket(1; compact = true),
        )

        @test SysInfo.numa(inuma) isa Vector{<:Integer}
        @test SysInfo.numa(inuma, 1:1) isa Vector{<:Integer}
        @test length(SysInfo.numa(inuma, 1:1)) == 1
        @test SysInfo.numa(inuma; compact = true) isa Vector{<:Integer}
        for cpuid in SysInfo.numa(inuma; compact = true)
            @test SysInfo.cpuid_to_numanode(cpuid) == inuma
        end
        _check_compactness(
            SysInfo.numa(1; compact = false),
            SysInfo.numa(1; compact = true),
        )

        @test SysInfo.node(icputhread) isa Vector{<:Integer}
        @test SysInfo.node(icputhread:icputhread) isa Vector{<:Integer}
        @test SysInfo.node(; compact = true) isa Vector{<:Integer}
        @test SysInfo.node(; compact = true) == SysInfo.cpuid.(1:SysInfo.ncputhreads())
        _check_compactness(SysInfo.node(; compact = false), SysInfo.node(; compact = true))

        @test SysInfo.cores() isa Vector{<:Integer}
        if SysInfo.ncores() > 1
            cpuids = SysInfo.cores()
            cores = SysInfo.Internals.cpuid_to_core.(cpuids)
            @test cores[1] != cores[2] || all(==(cores[1]), cores)
        end

        @test SysInfo.sockets() isa Vector{<:Integer}
        for cpuid in SysInfo.sockets()[1:SysInfo.nsockets()]
            SysInfo.Internals.cpuid_to_socket(cpuid) == 1:SysInfo.nsockets()
        end
        _check_compactness(
            SysInfo.sockets(; compact = false),
            SysInfo.sockets(; compact = true),
        )

        @test SysInfo.numas() isa Vector{<:Integer}
        for cpuid in SysInfo.numas()[1:SysInfo.nnuma()]
            SysInfo.cpuid_to_numanode(cpuid) == 1:SysInfo.nnuma()
        end
        _check_compactness(
            SysInfo.numas(; compact = false),
            SysInfo.numas(; compact = true),
        )
    end
end

function internal_tests()
    @testset "internal_tests" begin
        @test @views issorted(SysInfo.stdsys().matrix[:, IID])
        @test @views issorted(SysInfo.stdsys().matrix[:, ICORE])
        @test @views issorted(SysInfo.stdsys().matrix[:, INUMA])
        @test @views issorted(SysInfo.stdsys().matrix[:, ISOCKET])
        if SysInfo.nsmt() > 1
            @test !issorted(SysInfo.stdsys().matrix[:, ISMT])
        else
            @test issorted(SysInfo.stdsys().matrix[:, ISMT])
        end

        @testset "roundrobin" begin
            # equal length
            @test SysInfo.Internals.roundrobin([1, 2, 3, 4], [5, 6, 7, 8]) ==
                  [1, 5, 2, 6, 3, 7, 4, 8]
            @test SysInfo.Internals.roundrobin(1:4, 5:8) == [1, 5, 2, 6, 3, 7, 4, 8]
            @test SysInfo.Internals.roundrobin(1:4, 5:8, 9:12) ==
                  [1, 5, 9, 2, 6, 10, 3, 7, 11, 4, 8, 12]
            # unequal length
            @test SysInfo.Internals.roundrobin([1, 2], [3, 4, 5], [6, 7, 8, 9]) ==
                  [1, 3, 6, 2, 4, 7, 5, 8, 9]
            @test SysInfo.Internals.roundrobin(
                [3, 4, 5],
                [1, 2],
                [6, 7, 8, 9],
                [10, 11, 12, 13, 14, 15, 16],
            ) == [3, 1, 6, 10, 4, 2, 7, 11, 5, 8, 12, 9, 13, 14, 15, 16]
        end
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
            println("")
            @warn("\nTestSystem: $name\n")
            ts = TestSystems.load(name)
            TestSystems.with_testsystem(ts) do
                @testset "$name" begin
                    basic_tests()
                    index_tests()
                    internal_tests()
                    # check consistency between hwloc and lscpu backend (if possible)
                    if TestSystems.hashwloc(ts) && TestSystems.haslscpu(ts)
                        if name in ("DiracTestbedGPUNode",)
                            # DiracTestbedGPUNode:
                            #       Order of CPU/OS IDs doesn't match. Unclear how to fix this.
                        else
                            @info("→ performing consistency check")
                            @test SysInfo.Internals.check_consistency_backends(;
                                sys_hwloc = TestSystems.testsystem2system(
                                    ts;
                                    backend = :hwloc,
                                ),
                                sys_lscpu = TestSystems.testsystem2system(
                                    ts;
                                    backend = :lscpu,
                                ),
                            )
                        end
                    end
                end
            end
        end
        println()
    end
end
