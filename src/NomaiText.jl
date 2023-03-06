module NomaiText
using Luxor
using Statistics: mean

export grid_from_oracle!, Oracle, draw_spiral

import Base: *

##
# Global constants
##
K::Float64 = 20.0 # size of glyphs


include("glyph_types.jl")
include("oracles.jl")
#include("GlyphGrid.jl")
include("glyphgrid2.jl") # for development only, pick this or above
include("geometry.jl")
include("grid_layout.jl")
include("server.jl")



##
# Define core glyph digit shapes
##
include("digit_shapes.jl")

"""Return the basic Glyph for a GlyphDigit."""
core_glyph(::Type{T}) where {T <: AbstractGlyphDigit} = Glyph(_core_poly(T), nothing)

##
# Define a list of known glyphs
# These are a human curated set of core glyphs with annotations applied.
# Some combinations of core glyph and annotation don't look great, so we don't use them.
##
include("known_glyphs.jl") # defines KNOWN_GLYPHS


##
# Geometric queries on glyphs
##

"""Get all `Point`s in a `Glyph`."""
function allpoints(g::Glyph)
    if isnothing(g.annotation)
        return g.core.points
    else
        return vcat(g.core.points, g.annotation.points)
    end
end


##
# Making Glyph drawings!
##

"""
    draw(oracle::Oracle)
Draw an `Oracle` by building a `GlyphGrid` from it, then drawing that."""
draw(oracle::Oracle) = draw(grid_from_oracle!(oracle))

"""
    draw(glyphgrid::GlyphGrid)
Draw a `GlyphGrid` with a fully evenly spaced grid rectangular layout."""
draw(glyphgrid::GlyphGrid) = draw(LinearGridLayout(glyphgrid, DEFAULT_SPACING))

"""
    draw(gl::AbstractGridLayout, as_string::Bool)

Compute the drawing of a grid layout.
* `as_string = true`: return the drawing SVG as a string
* `as_string = false`: return a preview of the drawing; only renders nicely in VSCode,
  Pluto, etc.
"""
function draw(gl::AbstractGridLayout, as_string = false)
    width, height = drawing_size(gl)
    pic = @drawsvg begin
        # style
        setline(4)
        background("antiquewhite")
        setcolor("dodgerblue4")
        setlinecap(:round)
        setlinejoin(:round)
        # draw the glyphs themselves
        for ind in CartesianIndices(gl.grid.grid)
            hasglyph(gl, ind) || continue
            origin()
            transform(gl, ind)
            draw(gl.grid.grid[ind])
        end
        # draw glyph connections
        for conn in gl.grid.connections
            # move to starting glyph location
            origin()
            transform(gl, conn.coord1...)
            start = getworldposition(conn.point1)
            # move to ending glyph location
            origin()
            transform(gl, conn.coord2...)
            stop = getworldposition(conn.point2)
            # draw the line
            @layer begin
                origin()
                line(start, stop, :stroke)
                foreach(_vertex_circle, (start, stop))
            end
        end
    end width height
    as_string && return svgstring()
    return pic
end

"Draw a message in a spiral"
function draw_spiral(str; base = 256, as_string = false)
    grid = grid_from_oracle!(Oracle(str; base = base))
    needed_length = 3.5 * K * size(grid.grid, 1)
    local spath
    period = pi/4
    Drawing(100, 100, :svg) # needed so we can draw spirals and get their lengths
    while true
        newpath()
        spiral(164, .35, log = true, action = :path, period = period)
        spath = storepath()
        pathlength(spath) >= needed_length && break
        period += pi/24
    end
    @info "" period
    newpath()
    rotation_needed = pi - mod(period, 2pi)
    spath = rotatepath(spath, rotation_needed)
    draw(PathGridLayout(grid, spath), as_string)
end


"Annotate a vertex at `pt` with a small circle."
function _vertex_circle(pt, raw_rad = 5)
    avg_scale = mean(getscale())
    circle(pt, raw_rad / avg_scale, :fill)
end
    

"""Draw a polygon defined by a PolySpec on the current drawing. As is Nomai tradition,
non-terminal vertices are annotated with a small circle."""
function draw(p::PolySpec)
    poly(p.points; action = :stroke, close = p.close)
    circlepoints = p.close ? p.points : p.points[2:(end-1)]
    foreach(_vertex_circle, circlepoints)
end
function draw(g::Glyph)
    draw(g.core)
    if !isnothing(g.annotation)
        draw(g.annotation)
    end
end

##
# Visualization helpers
##

function vishelp(objects)
    spacing = 4K
    n = length(objects)
    nx = ceil(Int, sqrt(n))
    ny = ceil(Int, n / nx)
    width = nx * spacing
    height = ny * spacing
    @drawsvg begin
        background("antiquewhite")
        setlinecap(:round)
        setlinejoin(:round)
        tiles = Tiler(width, height, nx, ny; margin = 0)
        for (pt, i) in collect(tiles)
            i > n && continue
            @layer begin
                translate(pt)
                draw(objects[i])
            end
        end
    end width height
end


end # module NomaiText