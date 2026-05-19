module NomaiText
using Luxor
using Statistics: mean
using Random: Xoshiro

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
- `seed::Int = 47`: Integer used as RNG seed for handwriting. Ignored if `handwriting = 0`.

Return:
* `as_string = true`: return the drawing SVG as a string
* `as_string = false`: return a preview of the drawing; only renders nicely in VSCode,
    Pluto, etc.
"""
function draw_spiral(
    str::String;
    base = 256,
    as_string = false,
    handwriting = 0,
    seed = 47
)
    grid = grid_from_oracle!(Oracle(str; base = base))
    if handwriting > 0
        rng = Xoshiro(seed)
        grid = handwrite(grid, handwriting, rng)
    end
    needed_length = 3.5 * K * size(grid.grid, 1)
    local spath

    # Initialize a shared 1000x1000 canvas in memory to avoid repetitive allocations
    Drawing(1000, 1000, :svg) 

    # Step 1: Exponential search to dynamically determine the upper bound (hi) for long texts
    lo = pi/24
    hi = 2pi
    while true
        newpath()
        spiral(164, .29, log = true, action = :path, period = hi)
        spath = storepath()
        if pathlength(spath) >= needed_length
            break
        end
        lo = hi
        hi *= 1.5 # Safely scale up the bound for extremely long messages
    end
    
    # Step 2: Binary search within the resolved [lo, hi] interval for precise fitting
    for _ in 1:10  
        mid = (lo + hi) / 2
        newpath()
        spiral(164, .29, log = true, action = :path, period = mid)
        spath = storepath()
        if pathlength(spath) >= needed_length
            hi = mid
        else
            lo = mid
        end
    end
    
    # Step 3: Generate the final spiral path with the optimized period
    newpath()
    spiral(164, .29, log = true, action = :path, period = hi)
    spath = storepath()
    rotation_needed = pi - mod(hi, 2pi)
    spath = rotatepath(spath, rotation_needed)
    
    # Forward the live `spath` to layout directly to prevent redundant path reconstruction
    layout = PathGridLayout(grid, spath)
    
    if as_string
        # Hand off the active canvas seamlessly to the custom SVG string renderer
        return draw_svg(layout)
    else
        finish() # Close the drawing environment if using the default fallback rendering pipeline
        return draw(layout, as_string)
    end
end
"""Draw a message in a spiral with a Dict argument - useful for use with Jot.jl and AWS
Lambda. `argdict` must contain a `"message"` key with a string value, which is passed as
the positional argument to `draw_spiral(::String)`. Optionally include an `"id"` key with
a string value, which is used for the `id` of the resulting SVG.
Any further key-value pairs in `argdict` are passed as keyword arguments."""
function draw_spiral(argdict)
    args = deepcopy(argdict) # don't modify passed dict when we pop!
    message = pop!(args, "message")
    if haskey(args, "id")
        id = pop!(args, "id")
    else
        id = "nomai"
    end
    svg = draw_spiral(message; [Symbol(k) => v for (k,v) in args]...)
    if typeof(svg) == String
        # clean up the ID so the resulting SVG doesn't have a random-ish ID field
        r = r"(id\s*=\s*)\"([^\"]*)\"" # (id=)"(actual id)"
        return replace(svg, r => "id=\"$(id)\"")
    else
        return svg
    end
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

"""
    draw_svg(gl::AbstractGridLayout)

Build an SVG string for a grid layout directly.  Uses Luxor's `transform` and
`getworldposition` to compute world coordinates (guaranteed correct), then
writes raw `<line>` and `<circle>` tags instead of going through Luxor's
expensive stroke/fill pipeline.  Roughly 3-5× faster than `@drawsvg`.
"""
function draw_svg(gl::AbstractGridLayout)
    width, height = drawing_size(gl)

    # ---- step 1: collect world coordinates using Luxor's transform stack ----
    # We create a hidden drawing just to run the transform maths.
    Drawing(width, height, :svg)
    origin()                     # centre (width/2, height/2)

    # Per-glyph data: (world_points, n_core, n_anno, core_close, anno_close)
    glyph_data = Vector{Any}(undef, 0)

    for ind in CartesianIndices(gl.grid.grid)
        hasglyph(gl, ind) || continue
        origin()
        transform(gl, ind)
        glyph = gl.grid.grid[ind]

        core_pts  = glyph.core.points
        anno_pts  = isnothing(glyph.annotation) ? Point[] : glyph.annotation.points
        n_core    = length(core_pts)
        n_anno    = length(anno_pts)

        world_pts = [getworldposition(pt) for pt in vcat(core_pts, anno_pts)]
        push!(glyph_data, (
            world_pts,
            n_core,
            n_anno,
            glyph.core.close,
            isnothing(glyph.annotation) ? false : glyph.annotation.close,
        ))
    end

    # Connection data: (p1, p2)
    conn_data = Vector{Tuple{Point, Point}}(undef, 0)
    for conn in gl.grid.connections
        origin()
        transform(gl, conn.coord1...)
        p1 = getworldposition(conn.point1)
        origin()
        transform(gl, conn.coord2...)
        p2 = getworldposition(conn.point2)
        push!(conn_data, (p1, p2))
    end
    
    # Clean up the hidden drawing to prevent memory leaks!
    finish()

    # ---- step 2: build SVG string from the collected coordinates ----
    line_style = "stroke='#104E8B' stroke-width='4' stroke-linecap='round' stroke-linejoin='round'"
    circle_style = "r='3' fill='#104E8B'"
    cx = width / 2
    cy = height / 2

    svg_parts = String[
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $width $height\" width=\"$width\" height=\"$height\">",
        "<rect width=\"100%\" height=\"100%\" fill=\"antiquewhite\"/>",
    ]

    for (world_pts, n_core, n_anno, core_close, anno_close) in glyph_data
        n_total = n_core + n_anno
        
        # core edges
        for k in 1:(n_core - 1)
            A, B = world_pts[k], world_pts[k+1]
            push!(svg_parts, "<line x1='$(A.x + cx)' y1='$(A.y + cy)' x2='$(B.x + cx)' y2='$(B.y + cy)' $line_style/>")
        end
        if core_close && n_core > 0
            A, B = world_pts[n_core], world_pts[1]
            push!(svg_parts, "<line x1='$(A.x + cx)' y1='$(A.y + cy)' x2='$(B.x + cx)' y2='$(B.y + cy)' $line_style/>")
        end
        
        # annotation edges
        if n_anno > 0
            for k in (n_core + 1):(n_total - 1)
                A, B = world_pts[k], world_pts[k+1]
                push!(svg_parts, "<line x1='$(A.x + cx)' y1='$(A.y + cy)' x2='$(B.x + cx)' y2='$(B.y + cy)' $line_style/>")
            end
            if anno_close
                A, B = world_pts[n_total], world_pts[n_core + 1]
                push!(svg_parts, "<line x1='$(A.x + cx)' y1='$(A.y + cy)' x2='$(B.x + cx)' y2='$(B.y + cy)' $line_style/>")
            end
        end
        
        # vertex circles
        for pt in world_pts
            push!(svg_parts, "<circle cx='$(pt.x + cx)' cy='$(pt.y + cy)' $circle_style/>")
        end
    end

    # connections
    for (p1, p2) in conn_data
        push!(svg_parts, "<line x1='$(p1.x + cx)' y1='$(p1.y + cy)' x2='$(p2.x + cx)' y2='$(p2.y + cy)' $line_style/>")
        push!(svg_parts, "<circle cx='$(p1.x + cx)' cy='$(p1.y + cy)' $circle_style/>")
        push!(svg_parts, "<circle cx='$(p2.x + cx)' cy='$(p2.y + cy)' $circle_style/>")
    end

    push!(svg_parts, "</svg>")
    return join(svg_parts)
end


"""
    _glyph_edges(world_pts, n_core, n_anno, glyph)

Return a `Vector{Tuple{Point, Point}}` of edges that should be stroked
for a glyph whose vertices have already been transformed to world coordinates.
"""
function _glyph_edges(world_pts, n_core, n_anno, glyph)
    n_total = n_core + n_anno
    edges = Vector{Tuple{Point, Point}}(undef, 0)
    sizehint!(edges, n_core + n_anno)
    # Core polygon edges
    for k in 1:(n_core - 1)
        push!(edges, (world_pts[k], world_pts[k+1]))
    end
    if glyph.core.close
        push!(edges, (world_pts[n_core], world_pts[1]))
    end
    # Annotation polygon edges (if present)
    if n_anno > 0
        for k in (n_core + 1):(n_total - 1)
            push!(edges, (world_pts[k], world_pts[k+1]))
        end
        if glyph.annotation.close
            push!(edges, (world_pts[n_total], world_pts[n_core + 1]))
        end
    end
    return edges
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