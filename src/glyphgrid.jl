# Naming convention: "rows", "cols", etc. refer to the DRAWN output.
# Since we map (i,j) → (x,y) to keep coordinate order consistent Julia-to-Luxor,
# the Julia matrix is transposed relative to these names: ROWS is the Julia column
# count, and "col" functions operate on Julia rows.

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

Construct a `GlyphGrid` with `n_paths` branching paths. The grid matrix starts small
and expands horizontally as glyphs are added.

Indexing: `grid[i, j]` uses Julia matrix indexing. When drawn, `i` maps to Luxor's
x-axis (horizontal) and `j` to y-axis (vertical, fixed at `ROWS=3`).

Mapping grid locations to drawing coordinates is handled by `AbstractGridLayout` subtypes.
"""
mutable struct GlyphGrid
    grid::Matrix{MaybeGlyph}
    paths::Vector{Vector{Coord}}
    connections::Vector{GlyphConnection}
end

function GlyphGrid(n_paths::Int)
    return GlyphGrid(
        Array{MaybeGlyph}(nothing, n_paths, ROWS), # n_paths is just initial capacity; expands as needed
        [Coord[] for _ in 1:n_paths],
        GlyphConnection[]
    )
end

"Build a complete grid from an Oracle, consuming the Oracle in the process."
function grid_from_oracle!(oracle::Oracle; n_paths = 2)
    gg = GlyphGrid(2)
    while !iscomplete(oracle)
        next!(gg, oracle)
    end
    return truncate!(gg)
end

"""Concatenate two GlyphGrids left-to-right. Grids must agree on number of rows and paths.
The Oracle is used to connect paths between grids."""
function concatenate_grids!(oracle::Oracle, gg1::GlyphGrid, gg2::GlyphGrid)
    if size(gg1.grid, 2) != size(gg2.grid, 2) 
        error("Grids have discordant number of rows; cannot concatenate.")
    end
    if length(gg1.paths) != length(gg2.paths)
        error("Grids have discordant numbers of paths; cannot concatenate.")
    end

    # Matrices can be directly concatenated
    ncols_gg1 = _num_cols(gg1)
    grid = vcat(
        gg1.grid[1:ncols_gg1,:], # don't concatenate unused matrix
        gg2.grid
    )

    # But paths reference coordinates,
    # so we need to update coords in the appended part of each path.
    paths = deepcopy(gg1.paths)
    for (left_path, right_path) in zip(paths, gg2.paths)
        append!(left_path, [(c[1] + ncols_gg1, c[2]) for c in right_path])
    end

    # For connections, we also update coords for connections from the right grid.
    connections = deepcopy(gg1.connections)
    for conn in gg2.connections
        push!(connections, GlyphConnection(
            (conn.coord1[1] + ncols_gg1, conn.coord1[2]),
            conn.point1,
            (conn.coord2[1] + ncols_gg1, conn.coord2[2]),
            conn.point2
        ))
    end
    # Once the new grid is built, we use the provided Oracle to connect the two sections.
    gg_combined = GlyphGrid(grid, paths, connections)
    for (path_ind, path) in enumerate(gg_combined.paths)
        n_gg1 = length(gg1.paths[path_ind])
        _connect_glyphs!(gg_combined, oracle, path[n_gg1], path[n_gg1 + 1])
    end
    return gg_combined
end

"""Add a deep copy of Glyph at point (i,j) in a GlyphGrid."""
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
    gg.grid[i,j] = deepcopy(glyph)
end

"""The number of populated i-indices (horizontal positions when drawn) in a `GlyphGrid`."""
function _num_cols(gg::GlyphGrid) 
    max_i = findlast(vec(sum(hasglyph, gg.grid; dims=2)) .> 0)
    isnothing(max_i) && return 0
    return max_i
end

"""Trim unused i-indices from the end of a GlyphGrid's grid. Return the modified GlyphGrid."""
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
    for (head, new_pt) in unique(zip(path_heads, next_pts))
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