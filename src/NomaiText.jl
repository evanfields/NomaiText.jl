module NomaiText
using Luxor
using Statistics: mean

export grid_from_oracle!, Oracle, draw_spiral

import Base: *

##
# Global constants
##
K::Float64 = 20.0 # size of glyphs

##
# Define core glyph digit shapes. First types, then the shapes of our 16 "core digits",
# and finally a human-curated set of core glyphs with annotations.
##
include("glyph_types.jl")
include("digit_shapes.jl")
include("known_glyphs.jl") # defines KNOWN_GLYPHS

##
# Define Oracle, a type representing a message or other data as a BigInt and using
# that message to answer a sequence of "which choice?" questions.
##
include("oracles.jl")

include("geometry.jl") # geometric queries on glyphs and paths

##
# GlyphGrid is responsible for knowing what sequence of glyphs and connections to draw,
# but doesn't know about typesetting. It's the Nomai equivalent of a sequence of characters.
# Slight exception: for implementation reasons handwriting is implemented at the GlyphGrid
# level rather than the typesetting level.
##
include("glyphgrid.jl")
include("handwriting.jl")

##
# Layouts are responsible for typesetting. This defines linear and path (used for spiral)
# layouts.
#
include("grid_layout.jl")


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

"""
    draw_spiral(message::String; base = 256, as_string = false, handwriting = 0)

Draw a message in a spiral. Keyword arguments:
- `base::Int = 256`: Base of number system used to represent strings as a sequence of
    integers. To ensure that distinct messages cannot be rendered the same, `base`
    should be larger than the maximum codepoint you wish to support. Thus base 256
    works well for ASCII and base 200_000 works well for a set of unicode covering
    almost all symbols you're likely to encounter. Note that even with a smaller
    base, the probability that two distinct messages render the same is astronomically
    tiny. Spiral length is proportional to `log(base)`.
- `as_string::Bool = false`: controls return, see below.
- `handwriting::Float64 = 0`: Non-negative real number indicating the amount of glyph
    imperfection as if due to handwriting. See `NomaiText.handwrite` for more details.

Return:
* `as_string = true`: return the drawing SVG as a string
* `as_string = false`: return a preview of the drawing; only renders nicely in VSCode,
    Pluto, etc.
"""
function draw_spiral(str::String; base = 256, as_string = false, handwriting = 0)
    grid = grid_from_oracle!(Oracle(str; base = base))
    if handwriting > 0
        grid = handwrite(grid, handwriting)
    end
    needed_length = 3.5 * K * size(grid.grid, 1)
    local spath
    period = pi/4
    Drawing(100, 100, :svg) # needed so we can draw spirals and get their lengths
    while true
        newpath()
        spiral(164, .29, log = true, action = :path, period = period)
        spath = storepath()
        pathlength(spath) >= needed_length && break
        period += pi/24
    end
    newpath()
    rotation_needed = pi - mod(period, 2pi)
    spath = rotatepath(spath, rotation_needed)
    draw(PathGridLayout(grid, spath), as_string)
end
"""Draw a message in a spiral with a Dict argument - useful for use with Jot.jl and AWS
Lambda. `argdict` must contain a `"message"` key with a string value, which is passed as
the positional argument to `draw_spiral(::String)`. Any further key-value pairs in
`argdict` are passed as keyword arguments."""
function draw_spiral(argdict)
    args = deepcopy(argdict) # don't modify passed dict when we pop!
    message = pop!(args, "message")
    return draw_spiral(message; [Symbol(k) => v for (k,v) in args]...)
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
                @layer begin
                    setcolor("blue")
                    circle(O, 1, :fill)
                end
                draw(objects[i])
            end
        end
    end width height
end

end # module NomaiText