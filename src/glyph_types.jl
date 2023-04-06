##
# Basic types
##

"""Abstract type representing any of the known core glyphs which in turn can be seen as
base 16 digits."""
abstract type AbstractGlyphDigit end
const CORE_GLYPH_TYPES = DataType[]
for i in 0:15
    @eval struct $(Symbol("GlyphDigit$(i)")) <: AbstractGlyphDigit end
    @eval push!(CORE_GLYPH_TYPES,  $(Symbol("GlyphDigit$(i)")))
end

"""Information needed to draw a polygon with `poly`. Wraps `points` and `close`."""
struct PolySpec
    points::Vector{Point}
    close::Bool
end

*(ps::PolySpec, r::Real) = r * ps
*(r::Real, ps::PolySpec) = PolySpec(r .* ps.points, ps.close)

"""A glyph to be drawn: a `core`` glyph shape plus optional `annotation`."""
struct Glyph
    core::PolySpec
    annotation::Union{PolySpec, Nothing}
end

# scale glyphs
*(g::Glyph, r::Real) = r * g
*(r::Real, g::Glyph) = Glyph(r * g.core, isnothing(g.annotation) ? nothing : r * g.annotation)

const MaybeGlyph = Union{Glyph, Nothing}
hasglyph(mg::MaybeGlyph) = !isnothing(mg)

"""Return the basic Glyph for a GlyphDigit."""
core_glyph(::Type{T}) where {T <: AbstractGlyphDigit} = Glyph(_core_poly(T), nothing)
