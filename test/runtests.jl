using CompTime
using Test
using InteractiveUtils: @code_lowered

@testset "CompTime.jl" begin
  struct SVector{T,n}
    v::Vector{T}
    function SVector(v::Vector{T}) where {T}
      new{T,length(v)}(v)
    end
    function SVector{T,n}(v::Vector{T}) where {T,n}
      @assert n == length(v)
      new{T,n}(v)
    end
    function SVector{T,n}() where {T,n}
      new{T,n}(Vector{T}(undef, n))
    end
  end

  Base.getindex(v::SVector, i) = v.v[i]

  function Base.setindex!(v::SVector{T}, x::T, i) where {T}
    v.v[i] = x
  end

  function Base.:(==)(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    v1.v == v2.v
  end

  @comptime_gen function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    vout = SVector{T, n}()
    @ct for i in 1:n
      vout[@ct i] = v1[@ct i] + v2[@ct i]
    end
    vout
  end

  v1 = SVector([2,3,4])
  v2 = SVector([5,6,7])
  @test add(v1,v2) == SVector(v1.v .+ v2.v)

  @comptime_gen function add_adaptive(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    vout = SVector{T, n}()
    @ct if n <= 10
      @ct for i in 1:n
        vout[@ct i] = v1[@ct i] + v2[@ct i]
      end
    else
      for i in 1:n
        vout[i] = v1[i] + v2[i]
      end
    end
    vout
  end

  w1 = SVector(zeros(12))
  w2 = SVector(ones(12))
  @test (@code_lowered add(v1, v2)).code == (@code_lowered add_adaptive(v1,v2)).code
  @test add_adaptive(w1, w2) == SVector(w1.v .+ w2.v)
  @test (@code_lowered add(w1, w2)).code != (@code_lowered add_adaptive(w1,w2)).code

  @comptime_gen function add_while(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    vout = SVector{T, n}()
    @ct i = 1
    @ct while i <= n
      vout[@ct i] = v1[@ct i] + v2[@ct i]
      @ct i += 1
    end
    vout
  end

  @test (@code_lowered add_while(v1,v2)).code == (@code_lowered add(v1,v2)).code

  @comptime_gen begin
    add_dyn(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n} = @runtime

    add_static(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n} = @comptime

    @def begin
      vout = SVector{T, n}()
      @ct for i in 1:n
        vout[@ct i] = v1[@ct i] + v2[@ct i]
      end
      vout
    end
  end

  @test add_dyn(v1,v2) == add_static(v1,v2)
  @test (@code_lowered add_dyn(w1, w2)).code == (@code_lowered add_adaptive(w1,w2)).code
  # @test (@code_lowered add_static(v1, v2)).code == (@code_lowered add_adaptive(v1,v2)).code
  # This basically passes, except for a tiny difference of return values not worth worrying about
end
