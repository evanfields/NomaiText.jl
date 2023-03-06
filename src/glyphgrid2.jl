# This file started off as a copy of GlyphGrid.jl on 2023-2-26
# I'm exploring some other ways of organizing glyphs here

const ROWS = 3
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
    GlyphGrid(n_paths::Int)

Construct a `GlyphGrid` with `n_paths` paths. Initialize with 1 column;
`GlyphGrids` will automatically expand as needed when points are added.

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
    paths::Vector{Vector{Coord}}
    connections::Vector{GlyphConnection}

    function GlyphGrid(n_paths::Int)
        return new(
            Array{MaybeGlyph}(nothing, n_paths, ROWS),
            [Coord[] for _ in 1:n_paths],
            GlyphConnection[]
        )
    end
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
end

"""The number of populated columns (x-y space, aka rows i-j space) in a `GlyphGrid`."""
function _num_cols(gg::GlyphGrid) 
    max_i = findlast(vec(sum(hasglyph, gg.grid; dims=2)) .> 0)
    isnothing(max_i) && return 0
    return max_i
end

"""Trim unused columns (x-y) space [aka rows in i-j space] from the end of a
GlyphGrid's grid. Return the modified GlyphGrid."""
function truncate!(gg::GlyphGrid)
    ncols = _num_cols(gg)
    gg.grid = gg.grid[1:ncols, :]
    return gg
end

"""Show the arrangement of `Glyph`s in a `GlyphGrid`. Glyphs are just represented as filled
circles."""
function showgrid(gg::GlyphGrid)
    r = 10
    spacing = 3r
    n = size(gg.grid)[1]
    width = spacing * n
    height = spacing * ROWS
    # map (i,j) index in grid to point on drawing
    drawing_coords(i,j) = Point(
        i * spacing - width/2 - spacing/2,
        (j - (ROWS + 1)/2) * spacing
    )
    @drawsvg begin
        background("antiquewhite")
        for i in 1:n, j in 1:ROWS
            circle(
                drawing_coords(i,j),
                r;
                action = ifelse(hasglyph(gg.grid[i,j]), :fill, :stroke)
            )
        end
        for conn in gg.connections
            start = drawing_coords(conn.coord1...)
            stop = drawing_coords(conn.coord2...)
            line(start, stop; action = :stroke)
        end
    end width height
end

"""Use an Oracle to choose the next point after `head` in a path."""
function _next_point!(oracle::Oracle, head::Coord)
    i, j = head
    if j == 1
        j_choices = (1, 2)
    elseif j == ROWS
        j_choices = (ROWS - 1, ROWS)
    else
        j_choices = (j - 1, j, j + 1)
    end
    next_j = ask!(oracle, j_choices)
    return (i + 1, next_j)
end

"""Update a `GlyphGrid` by adding a new column of `Glyph`s to the grid and
connections to the previous `Glyph` column.
Use the passed `Oracle` for all decisions."""
function next!(gg::GlyphGrid, oracle::Oracle, glyph_choices = KNOWN_GLYPHS)
    # first glyph always at the midline, no connections needed
    if !any(hasglyph, gg.grid)
        addpoint!(gg, ask!(oracle, glyph_choices), STARTING_POINT...)
        for path in gg.paths
            push!(path, STARTING_POINT)
        end
        return
    end
    # paths are non-empty, so we can extend from each path head
    path_heads = [path[end] for path in gg.paths]
    # for each head, choose a next point
    next_pts = [_next_point!(oracle, head) for head in path_heads]
    sort!(next_pts; by = coord -> coord[2]) # prevent path X crossings
    for (path, pt) in zip(gg.paths, next_pts)
        push!(path, pt)
    end
    # get the unique next points and place glyphs there
    new_glyph_locs = unique(next_pts)
    for loc in new_glyph_locs
        addpoint!(gg, ask!(oracle, glyph_choices), loc...)
    end
    # for each head, add a connection between the current head and the next glyph
    for (head, new_pt) in zip(path_heads, next_pts)
        _connect_glyphs!(gg, oracle, head, new_pt)
    end
end

"""Add a `GlyphConnection` between the `Glyph`s stored at `coord1` and `coord2`.
Use the passed `Oracle` to choose how to connect."""
function _connect_glyphs!(gg::GlyphGrid, oracle::Oracle, coord1, coord2)
    offset = Point(DEFAULT_SPACING .* (coord2 .- coord1))
    point_prior, point_last = _shortest_connection!(
        oracle,
        allpoints(gg.grid[coord1...]),
        allpoints(gg.grid[coord2...]),
        offset
    )
    push!(gg.connections, GlyphConnection(
        coord1,
        point_prior,
        coord2,
        point_last,
    ))
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

function grid_from_oracle!(oracle::Oracle)
    gg = GlyphGrid(2)
    while !iscomplete(oracle)
        next!(gg, oracle)
    end
    return truncate!(gg)
end