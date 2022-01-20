using CompTime
using Documenter

DocMeta.setdocmeta!(CompTime, :DocTestSetup, :(using CompTime); recursive=true)

makedocs(;
    modules=[CompTime],
    authors="Owen Lynch <root@owenlynch.org> and contributors",
    repo="https://github.com/olynch/CompTime.jl/blob/{commit}{path}#{line}",
    sitename="CompTime.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://olynch.github.io/CompTime.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/olynch/CompTime.jl",
    devbranch="main",
)
