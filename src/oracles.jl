##
# Oracles are our decision-makers about how/what to draw
##

"""`Oracle`s transform messages into answers to "which of k" questions. Use via the
`iscomplete` and `ask!` functions."""
mutable struct Oracle
    state::BigInt
    const orig_state::BigInt
    completed::Bool
end
Oracle(x::Integer) = Oracle(BigInt(x), BigInt(x), false)
Oracle(digits::Vector{Int}, base::Integer) = Oracle(evalpoly(big(base), digits))
Oracle(message::AbstractString; base::Integer = 256) = Oracle(Int.(collect(message)), base)

"Does an `Oracle` have more answers to give?"
iscomplete(o::Oracle) = o.completed

"Ask an `Oracle` to choose from `1:k`, update its internal state, and return its choice."
function ask!(o::Oracle, k::Int)
    newstate, answer = divrem(o.state, k)
    if iszero(newstate)
        o.completed = true
        o.state = o.orig_state
    else
        o.state = newstate
    end
    return answer + 1
end
"""Ask an `Oracle` to choose from a finit set `options`, update its internal state, and
return its choice. For now, `options` must have indexing 1:length(options). If needed
we can relax that in the future."""
ask!(o::Oracle, options) = return options[ask!(o, length(options))]
