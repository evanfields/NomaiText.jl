using Luxor
using Random

const ROWS = 4
const MIDLINE = 1 + ROWS ÷ 2
const DESIRED_OPTIONS = 2 # how many options do we want for next grid point?
const ACCEPTABLE_OPTIONS = 1
const MAX_IN_COL = 2
const DEFAULT_SPACING = 4 * K # used when choosing connection points

const Coord = Tuple{Int, Int}
const STARTING_POINT = (1, MIDLINE)

"""A representation of a connection between two `Glyphs` in a `GlyphGrid`. `coord1` and
`coord2` refer to `(i,j)` coordinates in the grid. `point1` and `point2` are points
relative to the respective `Glyph`."""
struct GlyphConnection
    coord1::Coord
    point1::Point
    coord2::Coord
    point2::Point
end

"""
    GlyphGrid(max_length::Int)

Construct a `GlyphGrid` with `max_length` columns. Don't worry too much about picking a
good length; `GlyphGrids` will automatically expand as needed when points are added.

A `GlyphGrid` is responsible for building and tracking the sequence of `Glyphs`
within an abstract grid system. The `GlyphGrid` does not know how to map abstract grid
locations to coordinates in drawing space. For these functions, see `AbstractGlyphLayout`.

`GlyphGrid`s store `Glyph`s in an array in `i-j`` space, which you can think of as
respectively indicating the row and column of an ordinary Julia matrix. When drawn via
a layout, `i` corresponds to horizontal `x`, and `j` to vertical `y`. Since Luxor uses
a Y-down coordinate system, it's as if the drawn grid is the transpose of the Julia
array stored in a `GlyphGrid`'s `grid` field.
"""
mutable struct GlyphGrid
    grid::Matrix{MaybeGlyph}
    path::Vector{Coord}
    connections::Vector{GlyphConnection}

    function GlyphGrid(max_length::Int)
        return new(
            Array{MaybeGlyph}(nothing, max_length, ROWS),
            Coord[],
            GlyphConnection[],
        )
    end
end

"""Whether it'd be valid to add a point to a GlyphGrid as the next point. The primary
criterion for validity is that the grid could easily continue from that point, rather
than being boxed in. A point must also be in bounds to be valid."""
function valid_next(gg::GlyphGrid, i, j)
    # The point must be in bounds. No need to check x too large, since we can always
    # expand the grid as necessary.
    if i < 1 || j < 1 || j > ROWS
        return false
    end
    # Can't already have too many glyphs in this column
    if (i <= size(gg.grid, 1)) && (sum(hasglyph, gg.grid[i,:]) >= MAX_IN_COL)
        return false
    end
    return iszero(sum(hasglyph, gg.grid[i:end, j]; init = false))
end

"""Add a Glyph at point (i,j) in a GlyphGrid."""
function addpoint!(gg::GlyphGrid, glyph::Glyph, i, j)
    # may need to expand the grid
    if i > size(gg.grid, 1)
        gg.grid = vcat(
            gg.grid,
            Array{MaybeGlyph}(nothing, 2 * size(gg.grid, 1), size(gg.grid, 2))
        )
    end
    if hasglyph(gg.grid[i,j])
        @warn "Tried to add point $((i,j)) but it was already used"
    end
    gg.grid[i,j] = glyph
    push!(gg.path, (i,j))
end

"""Trim unused columns (x-y) space [aka rows in i-j space] from the end of a
GlyphGrid's grid. Return the modified GlyphGrid."""
function truncate!(gg::GlyphGrid)
    max_i = maximum(c[1] for c in gg.path)
    gg.grid = gg.grid[1:max_i, :]
    return gg
end

"""Show the path of `Glyph`s in a `GlyphGrid`. Glyphs are just represented as filled
circles."""
function showgrid(gg::GlyphGrid)
    r = 10
    spacing = 3r
    n = size(gg.grid)[1]
    width = spacing * n
    height = spacing * ROWS
    # map (i,j) index in grid to point on drawing
    coords(i,j) = Point(
        i * spacing - width/2 - spacing/2,
        (j - (ROWS + 1)/2) * spacing
    )
    @drawsvg begin
        background("antiquewhite")
        for i in 1:n, j in 1:ROWS
            circle(coords(i,j), r; action = ifelse(hasglyph(gg.grid[i,j]), :fill, :stroke))
        end
        if length(gg.path) >= 2
            for i in 2:length(gg.path)
                start = coords(gg.path[i-1]...)
                stop = coords(gg.path[i]...)
                line(start, stop; action = :stroke)
            end
        end
    end width height
end

function _choose_next_ij!(oracle::Oracle, gg::GlyphGrid)
    if isempty(gg.path) # first glyph always at the midline
        return STARTING_POINT
    end
    cur_i, cur_j = gg.path[end]
    options = Tuple{Int, Int}[]
    # first try tucking diagonally back or going straight up-down
    for x in (cur_i - 1, cur_i), y in (cur_j - 1, cur_j + 1)
        valid_next(gg, x, y) && push!(options, (x, y))
    end
    length(options) >= DESIRED_OPTIONS && return ask!(oracle, options)
    # okay we can try moving one column forward
    for y in (cur_j - 1) : (cur_j + 1)
        valid_next(gg, cur_i + 1, y) && push!(options, (cur_i + 1, y))
    end
    length(options) >= ACCEPTABLE_OPTIONS && return ask!(oracle, options)
    # maybe we need to go one column forward but two rows up/down?
    for y in (cur_j - 2, cur_j + 2)
        valid_next(gg, cur_i + 1, y) && push!(options, (cur_i + 1, y))
    end
    length(options) >= ACCEPTABLE_OPTIONS && return ask!(oracle, options)
    # okay fine we'll go two columns forward and up to one row up/down
    for y in (cur_j - 1, cur_j + 1)
        valid_next(gg, cur_i + 2, y) && push!(options, (cur_i + 2, y))
    end
    return ask!(oracle, options)
end

"""Return a pair of `Point`s `(a ∈ ptsA, b ∈ ptsB)` such that the distance from `a` to
`b + offset` is minimized. If there are multiple pairs of points with equivalent (to within
`thresh`) distance, use the provided `Oracle` to pick one pair."""
function _shortest_connection!(oracle::Oracle, ptsA, ptsB, offset, thresh = .01)
    best_dist = Inf
    pairs = Tuple{Point, Point}[]
    for ptA in ptsA, ptB in ptsB
        dist = distance(ptA, ptB + offset)
        if dist <= best_dist - thresh # unique best optional
            empty!(pairs)
            push!(pairs, (ptA, ptB))
        elseif dist < best_dist + thresh # acceptable option
            push!(pairs, (ptA, ptB))
        end
        best_dist = min(dist, best_dist)
    end
    return ask!(oracle, pairs)
end

"""Update a `GlyphGrid` by adding a new `Glyph` to the grid and a connection to the
previous last `Glyph`. Use the passed `Oracle` for all decisions."""
function next!(gg::GlyphGrid, oracle::Oracle, glyph_choices = KNOWN_GLYPHS)
    # where should the next glyph go?
    next_i, next_j = _choose_next_ij!(oracle, gg)
    # choose the glyph and put it there
	addpoint!(gg, ask!(oracle, glyph_choices), next_i, next_j)
    if length(gg.path) > 1 # need a new connector
        coord_prior = gg.path[end - 1]
        coord_last = gg.path[end]
        offset = Point(DEFAULT_SPACING .* (coord_last .- coord_prior))
        point_prior, point_last = _shortest_connection!(
            oracle,
            allpoints(gg.grid[coord_prior...]),
            allpoints(gg.grid[coord_last...]),
            offset
        )
        push!(gg.connections, GlyphConnection(
            coord_prior,
            point_prior,
            coord_last,
            point_last,
        ))
    end
	return (next_i, next_j)
end


function grid_from_oracle!(oracle::Oracle)
    gg = GlyphGrid(1)
    while !iscomplete(oracle)
        next!(gg, oracle)
    end
    return truncate!(gg)
end