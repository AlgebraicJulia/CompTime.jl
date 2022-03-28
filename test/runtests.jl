using CompTime
using Test

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

  @ct_enable function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    vout = SVector{T, n}()
    @ct_ctrl for i in 1:n
      vout[@ct i] = v1[@ct i] + v2[@ct i]
    end
    vout
  end

  v1 = SVector([2,3,4])
  v2 = SVector([5,6,7])
  @test add(v1,v2) == SVector(v1.v .+ v2.v)
  @test add(v1,v2) == runtime(add, v1, v2)

  @ct_enable function add_adaptive(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    vout = SVector{T, n}()
    @ct_ctrl if n <= 10
      @ct_ctrl for i in 1:n
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
  @test add_adaptive(w1, w2) == SVector(w1.v .+ w2.v)
  @test add_adaptive(w1, w2) == runtime(add_adaptive, w1, w2)

  @ct_enable function add_while(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
    vout = SVector{T, n}()
    @ct i = 1
    @ct_ctrl while i <= n
      vout[@ct i] = v1[@ct i] + v2[@ct i]
      @ct i += 1
    end
    vout
  end

  @test add_while(v1, v2) == SVector(v1.v .+ v2.v)
  @test add_while(v1, v2) == runtime(add_while, v1, v2)
end
