module CompTime
export @ct_enable, runtime, comptime, generate_code, debug

"""
Notes:

Currently does not work with kwargs. These are tricky to handle correctly, so as a proof of concept, we do not handle them.
"""

using MLStyle
using MacroTools: splitdef, combinedef, @capture, postwalk, prewalk

function runtime end
function comptime end
function generate_code end

function debug(fn, args...)
  generate_code(fn, map(typeof, args)...)
end

macro ct_enable(args...)
  is_optional, def = @match args begin
    (:(optional=$(b::Bool)), def::Expr) && if def.head == :function end => (b, def)
    (def::Expr,) && if def.head == :function end => (true, def)
    _ => error("Invalid arguments $args")
  end
  @assert def.head == :function
  parts = FunctionParts(def)
  esc(quote
    $(make_apply_def(parts))

    $(make_generate_code_def(parts))

    $(make_comptime_def(parts, is_optional))

    $(make_runtime_def(parts))
  end)
end

struct FunctionParts
  name::Any
  args::Vector{Expr}
  whereparams::Any
  body::Any
  function FunctionParts(def::Expr)
    parts = splitdef(def)
    @assert parts[:kwargs] == []
    new(parts[:name], normalize_args(parts[:args]), parts[:whereparams], parts[:body])
  end
  function FunctionParts(name, args, whereparams, body)
    new(name, args, whereparams, body)
  end
end

function arg_names(parts::FunctionParts)
  map(parts.args) do arg
    @match arg begin
      Expr(:(::), name, _) => name
    end
  end
end

function arg_types(parts::FunctionParts)
  map(parts.args) do arg
    @match arg begin
      Expr(:(::), _, type) => type
    end
  end
end

function make_function(parts::FunctionParts)
  combinedef(Dict(
    :name=>parts.name,
    :args=>parts.args,
    :whereparams=>parts.whereparams,
    :body=>parts.body,
    :kwargs=>[]
  ))
end

function normalize_args(args::Vector)
  map(args) do arg
    @match arg begin
      Expr(:(::), name, type) => Expr(:(::), name, type)
      Expr(:(::), type) => Expr(:(::), gensym(), type)
      name::Symbol => Expr(:(::), name, Any)
      _ => error("unsupported argument format $arg")
    end
  end
end

function make_runtime_def(parts::FunctionParts)
  make_function(FunctionParts(
    GlobalRef(CompTime, :runtime),
    [Expr(:(::), Expr(:call, typeof, parts.name)), parts.args...],
    parts.whereparams,
    postwalk(strip_ct_macros, parts.body)
  ))
end

function make_comptime_def(parts::FunctionParts, is_optional)
  
  make_function(FunctionParts(
    GlobalRef(CompTime, :comptime),
    [Expr(:(::), Expr(:call, typeof, parts.name)), parts.args...],
    parts.whereparams,
    quote
      if $(Expr(:generated))
        $(generate_code)($(parts.name), $(arg_types(parts)...))
      else
        $(is_optional ? :($(runtime)($(parts.name), $(arg_names(parts)...))) : Expr(:meta, :generated_only))
      end
    end
  ))
end

function make_generate_code_def(parts::FunctionParts)
  type_args = map(arg_types(parts)) do type
    Expr(:(::), Expr(:curly, Type, type))
  end

  make_function(FunctionParts(
    GlobalRef(CompTime, :generate_code),
    [Expr(:(::), Expr(:call, typeof, parts.name)), type_args...],
    parts.whereparams,
    comptime_expr(parts.body)
  ))
end

function make_apply_def(parts::FunctionParts)
  make_function(FunctionParts(
    parts.name,
    parts.args,
    parts.whereparams,
    Expr(:call, comptime, parts.name, arg_names(parts)...)
  ))
end

function comptime_loop(mkloop, body)
  lines = gensym("lines")
  mkbody = comptime_expr(body)
  quote
    $lines = []
    $(mkloop(:(push!($lines, $mkbody))))
    Expr(:block, $lines...)
  end
end

function comptime_if(parts)
  branches = normalize_if(parts...)
  (cond, thenpart) = branches[1]
  rest = branches[2:end]
  Expr(:if, cond, comptime_expr(thenpart), comptime_else(rest))
end

function comptime_else(branches)
  if length(branches) > 0
    (cond, thenpart) = branches[1]
    Expr(:elseif, cond, comptime_expr(thenpart), comptime_else(branches[2:end]))
  else
    nothing
  end
end

function normalize_if(cond, thenpart)
  [(cond, thenpart)]
end

function normalize_if(cond, thenpart, elsepart)
  [(cond, thenpart), normalize_else(elsepart)...]
end

function normalize_else(elsepart)
  @match elsepart begin
    Expr(:elseif, cond, thenpart) =>
      [(cond, thenpart)]
    Expr(:elseif, cond, thenpart, moreelse) =>
      [(cond, thenpart), normalize_else(moreelse)...]
    _ => [(true, elsepart)]
  end
end

q(s::Symbol) = Expr(:quote, s)
q(e::Expr) = Expr(:quote, e)
q(x) = x

function ct_control(expr)
  generator = @match expr begin
    Expr(:for, head, body) =>
      comptime_loop(gen -> Expr(:for, head, gen), body)
    Expr(:if, parts...) =>
      comptime_if(parts)
    Expr(:while, cond, body) =>
      comptime_loop(gen -> Expr(:while, cond, gen), body)
    _ => error("unsupported control structure $expr")
  end
  Expr(:$, generator)
end

function expand_ct_macros(expr)
  @match expr begin
    Expr(:macrocall, mname, _, e) =>
      if mname == Symbol("@ct")
        Expr(:$, Expr(:call, q, e))
      elseif mname == Symbol("@ct_ctrl")
        ct_control(e)
      else
        expr
      end
    _ => expr
  end
end

function strip_ct_macros(expr)
  @match expr begin
    Expr(:macrocall, mname, _, e) =>
      if mname == Symbol("@ct")
        e
      elseif mname == Symbol("@ct_ctrl")
        e
      else
        expr
      end
    _ => expr
  end
end

function comptime_expr(expr)
  Expr(:quote, postwalk(expand_ct_macros, expr))
end

end
