# CompTime

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://olynch.github.io/CompTime.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://olynch.github.io/CompTime.jl/dev)
[![Build Status](https://github.com/olynch/CompTime.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/olynch/CompTime.jl/actions/workflows/CI.yml?query=branch%3Amain)


The goal of this library is to allow for a simplified style of writing
`@generated` functions, inspired by zig comptime features.

# Get Started

(minimal example)

# Theory

The core feature of CompTime is the ability to write functions that optionally have some of their code pre-run at compile time.

The central tenet of CompTime is that this *does not* allow you to write anything that you would not otherwise be able to write, from a semantics perspective. However, having a function partially evaluated at compile time may enable functions that would normally not be type checkable to be type checked, so from a type-checking standpoint this is a win, and of course having a function partially evaluated at compile time enables all sorts of other speedups.

Every function declared with `@ct_enable` can be used in three modes.
2. Compile-time mode. This compiles the function specially for the compile-time arguments to the function, and then runs the function. Under the hood, this uses `@generated` functions, and passes in all of the compile-time parameters as types, so this compilation is cached just like a normal `@generated` function, as long as all of the compile-time parameters can be resolved using constant-propagation.
1. Run-time mode. This does no compile-time computation, and just runs the function as if all of the macros from CompTime.jl were not there.
3. Syntax mode. This outputs the syntax that *would* be compiled for arguments of a certain type. This is very useful for debugging.

The arguments available at compile time are precisely the type arguments in the `where` clause.

Here's an example. Suppose we have a type of static vectors, here written for simplicity as a wrapper around the type of normal vectors.

```julia
struct SVector{T,n}
  v::Vector{T}
  function SVector(v::Vector{T}) where {T}
    new{T,length(v)}(v)
  end
  function SVector{T,n}(v::Vector{T}) where {T,n}
    assert(n == length(v))
    new{T,n}(v)
  end
  function SVector{T,n}() where {T,n}
    new{T,n}(Vector{T}(undef,n))
  end
end
```

Then we can write the following function to unroll a for-loop to add two static vectors.
```julia
@ct_enable function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  vout = SVector{(@ct T), (@ct n)}()
  @ct_ctrl for i in 1:n
    vout[@ct i] = v1[@ct i] + v2[@ct i]
  end
  vout
end
```

This should be roughly equivalent to the following code

```julia
function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  comptime(add, v1, v2)
end

function generate_code(::typeof(add), ::Type{SVector{T,n}}, ::Type{SVector{T,n}}) where {T,n}
  Expr(:block,
    :(vout = SVector{$T}(Vector{$T}(undef, $n))),
    begin
      code = Expr(:block)
      for i in 1:n
        push!(code.args, :(vout[$i] = v1[$i] + v2[$i]))
      end
      code
    end,
    :(vout)
  )
end

function comptime(::typeof(add), v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  if @generated
      generate_code(add, SVector{T,n}, SVector{T,n})
  else
      runtime(add, v1, v2)
  end
end

function runtime(::typeof(add), v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  vout = SVector{T,n}()
  for i in 1:n
    vout[i] = v1[i] + v2[i]
  end
  vout
end
```
Note that the above is an [**optionally** generated function](https://docs.julialang.org/en/v1/manual/metaprogramming/#Optionally-generated-functions), so the compiler is allowed to choose to use the runtime version in dynamic circumstances. If you do not wish to allow the compiler to make this choice, then instead write
```julia
@ct_enable optional=false function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  vout = SVector{(@ct T), (@ct n)}()
  @ct_ctrl for i in 1:n
    vout[@ct i] = v1[@ct i] + v2[@ct i]
  end
  vout
end
```
which will create a non-optional generated function. 
