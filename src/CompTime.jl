raw"""
The goal of this library is to allow for a simplified style of writing
@generated functions, inspired by zig comptime features.

Here's an example.

```julia
struct SVector{T,n}
  v::Vector{T}
  function SVector{T}(v::Vector{T}) where {T}
    new{T,length(v)}(v)
  end
  function SVector{T,n}(v::Vector{T}) where {T,n}
    assert(n == length(v))
    new{T,n}(v)
  end
end

@comptime_gen function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  vout = SVector{(@ct T), (@ct n)}(Vector{@ct T}(undef, @ct n))
  @ct for i in 1:n
    vout[@ct i] = v1[@ct i] + v2[@ct i]
  end
  vout
end
```

This should be equivalent to the following code

```julia
@generated function add(v1::SVector{T,n}, v2::SVector{T,n}) where {T,n}
  code = Expr(:block)
  push!(code.args, :(vout = SVector{$T}(Vector{$T}(undef, $n))))
  for i in 1:n
    push!(code.args, :(vout[$i] = v1[$i] + v2[$i]))
  end
  push!(code.args, :(vout))
  code
end
```
"""
module CompTime
export make_comptime, make_comptime_body, expand_ct, @comptime_gen

using MLStyle
using MacroTools: splitdef, combinedef, @capture, postwalk

macro comptime_gen(def)
  parts = splitdef(def)
  parts[:body] = make_comptime_body(parts[:body])
  esc(combinedef(parts))
end

function make_comptime_body(body)
  code_var = gensym("code")
  code = Expr(:block, :($code_var = Expr(:block)))
  @capture(body, begin lines__ end) || error("body should be a block of code")
  for line in lines
    push!(code.args, make_comptime(line, code_var))
  end
  push!(code.args, :($code_var))
  quote
    if $(Expr(:generated))
      $code
    else
      $(Expr(:meta, :generated_only))
      return
    end
  end
end

function make_comptime(line, code_var)
  @match line begin
    Expr(:macrocall, mname, _, control_structure) && if mname == Symbol("@ct") end =>
      @match control_structure begin
        Expr(:for, head, body) =>
          Expr(:for, head, make_comptime(body, code_var))
        Expr(:if, cond, thenpart, elsepart) =>
          Expr(:if, cond, make_comptime(thenpart, code_var), make_comptime_else(elsepart, code_var))
        Expr(:while, cond, body) =>
          Expr(:while, cond, make_comptime(body, code_var))
        # except for the special control structures, we just let it happen at compile time
        _ => control_structure
      end
    Expr(:block, lines...) =>
        Expr(:block, make_comptime.([lines...], Ref(code_var))...)
    expr => :(push!($code_var.args, $(Expr(:quote, expand_ct(expr)))))
  end
end

function make_comptime_else(elsepart, code_var)
  @match elsepart begin
    Expr(:elseif, cond, then) =>
      Expr(:elseif, cond, make_comptime(then, code_var))
    Expr(:elseif, cond, then, more_else) =>
      Expr(:elseif, cond, make_comptime(then, code_var), make_comptime_else(more_else, code_var))
    _ => make_comptime(elsepart, code_var)
  end
end

function expand_ct(expr)
  postwalk(x -> @capture(x, @ct e_) ? Expr(:$, e) : x, expr)
end

end
