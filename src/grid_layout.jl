"""Abstract type for Glyph layouts. A functional layout must include `grid::GlyphGrid`
and have implemented the `transform` method which applies Luxor translation/rotation/
scaling (from `origin()`) needed to draw the specified Glyph."""
abstract type AbstractGridLayout end

"A layout uses its grid to tell if there's a glyph at abstract (i,j) coords."
hasglyph(lgl::AbstractGridLayout, args...) = hasglyph(lgl.grid.grid[args...])

##
# Linear layout
##

mutable struct LinearGridLayout <: AbstractGridLayout
    grid::GlyphGrid
    coords::Matrix{Point}
    # governs desired spacing behavior - mutate these directly if needed?
    deltas::AbstractVector{Float64}
    req_between::Float64
end

transform(lgl::LinearGridLayout, args...) = translate(lgl.coords[args...])

"""Initialize an uncomputed LinearGridLayout from a `GlyphGrid`."""
function LinearGridLayout(gg::GlyphGrid)
    return LinearGridLayout(
        gg,
        [Point(NaN, NaN) for _ in gg.grid],
        range(start = 3.5 * K, stop = 6K, length = 20),
        .25 * K
    )
end

"""
    LinearGridLayout(gg::GlyphGrid, spacing::Real)

Define a naive LinearGridLayout which arrays glyphs on a perfectly regular grid with
glyph center-to-center distance `spacing`."""
function LinearGridLayout(gg::GlyphGrid, spacing::Real)
    ni, nj = size(gg.grid)
    coords = [spacing * Point(i - (ni+1)/2, (j - (nj+1)/2)) for i in 1:ni, j in 1:nj]
    return LinearGridLayout(gg, coords, Float64[spacing], spacing)
end


"""`(width, height)` of a drawing canvas to fit a `LinearGridLayout`,
counting some padding."""
function drawing_size(lgl::LinearGridLayout)
    padding = 2 * default_spacing(lgl)
    locs = [lgl.coords[i] for i in eachindex(lgl.coords) if hasglyph(lgl, i)]
    return (
        padding + maximum(pt.x for pt in locs) - minimum(pt.x for pt in locs),
        padding + maximum(pt.y for pt in locs) - minimum(pt.y for pt in locs),
    )
end

default_spacing(lgl::LinearGridLayout) = minimum(lgl.deltas)

"""Update the `(i,j)`-th Glyph's x-coordinate, if a `Glyph` is present."""
function _setx!(lgl, i, j, x)
    if hasglyph(lgl, i, j)
        lgl.coords[i,j] = Point(x, lgl.coords[i,j].y)
    end
    return
end
"""Update the `(i,j)`-th Glyph's y-coordinate, if a `Glyph` is present."""
function _sety!(lgl, i, j, y)
    if hasglyph(lgl, i, j)
        lgl.coords[i,j] = Point(lgl.coords[i,j].x, y)
    end
    return
end

"""Do the glyphs at two abstract `(i,j)` coords intersect in a linear layout?"""
function intersects(lgl::LinearGridLayout, i1, j1, i2, j2)
    if !hasglyph(lgl, i1, j1) || !hasglyph(lgl, i2, j2)
        return false
    end
    offset = lgl.coords[i2, j2] - lgl.coords[i1, j1]
    return intersects(lgl.grid.grid[i1, j1], lgl.grid.grid[i2, j2], offset)
end

"""Update the Y coordinate for each Glyph. X coordinates are ignored."""
function _compute_vertical_spacing!(lgl::LinearGridLayout)
    for i in 1:size(lgl.coords, 1)
        _compute_vertical_spacing!(lgl, i)
    end
end
function _compute_vertical_spacing!(lgl::LinearGridLayout, i::Int)
    nj = size(lgl.coords, 2)
    bad_spacing = minimum(lgl.deltas) - lgl.req_between
    for spacing in lgl.deltas # each potential spacing, starting dense
        # set vertical spacing
        for j in 1:nj
            _sety!(lgl, i, j, (j - (nj + 1) / 2) * spacing)
        end
        # if we don't have enough space over something that caused intersections,
        # we need a larger space, no need to check intersections
        if spacing < bad_spacing + lgl.req_between
            continue
        end
        # break if this spacing doesn't create intersections
        if !any(j -> intersects(lgl, i, j-1, i, j), 2:nj)
            break
        end
        # this spacing is bad, created an intersection
        bad_spacing = spacing
    end
    # even if there was an intersection at maximum spacing, we still accept
    return
end

"""Update the X coordinate for each Glyph. Y coordinates inform feasibility but are not updated."""
function _compute_horizontal_spacing!(lgl::LinearGridLayout)
    ni, nj = size(lgl.coords)
    # set first column X-coords to zero
    foreach(j -> _setx!(lgl, 1, j, 0), 1:nj)
    for i in 2:ni # every subsequent column
        bad_spacing = minimum(lgl.deltas) - lgl.req_between
        for spacing in lgl.deltas # each potential spacing, starting dense
            # set this horizontal spacing
            x = maximum(
                    lgl.coords[i-1,j].x for j in 1:nj if hasglyph(lgl, i-1, j)
                ) + spacing
            foreach(j -> _setx!(lgl, i, j, x), 1:nj)
            # if we don't have enough space over something that caused intersections,
            # we need a larger space, no need to check intersections
            if spacing < bad_spacing + lgl.req_between
                @info "Continuing" spacing bad_spacing lgl.req_between
                continue
            end
            # break if this spacing doesn't create intersections
            if !any(j -> intersects(lgl, i-1, j, i, j), 1:nj)
                break
            end
            # this spacing created an intersection
            bad_spacing = spacing
        end # either we got to max spacing, or found a smaller spacing with no intersection
    end
    # zero center coords around the x=0 axis
    minx, maxx = extrema(
        lgl.coords[ind].x
        for ind in eachindex(lgl.coords)
        if hasglyph(lgl, ind)
    )
    lgl.coords .+= Point(
        -(maxx - minx) / 2 - minx,
        0
    )
    return
end

"""Compute a linear grid layout"""
function compute!(lgl::LinearGridLayout)
    for i in eachindex(lgl.coords)
        if hasglyph(lgl, i)
            lgl.coords[i] = Point(0, 0)
        end
    end
    _compute_vertical_spacing!(lgl)
    _compute_horizontal_spacing!(lgl)
    return lgl
end

##
# Path layout
##

mutable struct PathGridLayout <: AbstractGridLayout
    grid::GlyphGrid
    path::Path
    max_scale::Float64
    ## precomputed path attributes, saves time
    pathlen::Float64
    bounding_box::BoundingBox
    ps_log::Dict{Float64, Tuple{Point, Float64}}

    function PathGridLayout(grid, path)
        max_scale = 2.0
        pathlen = pathlength(path)
        bb = BoundingBox(path)
        ni = size(grid.grid, 1)
        # Precompute all path points and slopes
        ps_log = Dict{Float64, Tuple{Point, Float64}}()
        if ni > 1
            Δ = (max_scale - 1) / (ni - 1)
            total_segment_length = (ni - 1) + 1/2 * (ni - 1)^2 * Δ
            for i in 1:ni
                cumulative_segment_length = (i - 1) + 1/2 * (i - 1)^2 * Δ
                k = cumulative_segment_length / total_segment_length
                # Precompute _pointslope for this k (will be stored in ps_log)
                ps_log[k] = _compute_pointslope(path, pathlen, k)
            end
        end
        return new(grid, path, max_scale, pathlen, bb, ps_log)
    end
end



"""Compute a tuple `(point, slope)` of the point a factor `k` along a path layout's path
plus the tangent slope there."""
function _pointslope(pgl::PathGridLayout, k::Float64)
    # All values are precomputed, so this is O(1) lookup (or fallback if somehow missing)
    k in keys(pgl.ps_log) && return pgl.ps_log[k]
    # Fallback: compute on the fly (should rarely happen)
    return _compute_pointslope(pgl.path, pgl.pathlen, k, pgl.ps_log)
end

"""Actually compute a point and slope by drawing the path. Called during precomputation."""
function _compute_pointslope(path, pathlen, k::Float64, ps_log::Dict = Dict{Float64, Tuple{Point, Float64}}())
    center = abs(k - .5) < .01 ? .51 : .5
    delta = .001 * sign(center - k)
    fracs = sort([k, k + delta])
    ptA = drawpath(path, fracs[1]; action = :none, startnewpath = true, pathlength = pathlen)
    ptB = drawpath(path, fracs[2]; action = :none, startnewpath = true, pathlength = pathlen)
    newpath()
    ptK = fracs[1] == k ? ptA : ptB
    tup = ptK, slope(ptA, ptB)
    ps_log[k] = tup
    return tup
end

function transform(pgl::PathGridLayout, i, j)
    ni, nj = size(pgl.grid.grid)
    Δ = (pgl.max_scale - 1) / (ni - 1) # increase in scale glyph to glyph
    total_segment_length = (ni - 1) + 1/2 * (ni - 1)^2 * Δ
    cumulative_segment_length = (i - 1) + 1/2 * (i - 1)^2 * Δ
    k = cumulative_segment_length / total_segment_length
    scale_here = 1 + (i - 1) * Δ
    # The "bottom line" is the line where j = nj, since when not rotated, higher j
    # means larger y means lower down the page. pgl's path is the bottom line of glyphs, so
    # the glyph centers extend radially outward from the path.
    bottomline_pt, slope = _pointslope(pgl, k)
    from_midline_pt = rotatepoint(Point(0, (j - nj) * 3K * scale_here), O, slope)
    point = bottomline_pt + from_midline_pt - midpoint(pgl.bounding_box)
    translate(point)
    rotate(slope)
    scale((pgl.max_scale - 1) * k + 1)
end
transform(pgl::PathGridLayout, ind::CartesianIndex) = transform(pgl, ind[1], ind[2])

"""`(width, height)` of a drawing canvas to fit a `PathGridLayout`,
counting some padding."""
function drawing_size(pgl::PathGridLayout)
    bb = pgl.bounding_box
    nj = size(pgl.grid.grid, 2)
    padding = max(
        12K + (nj - 1) * 4 * K * 2 * pgl.max_scale, # const + fit glyphs on both sides
        .05 * boxwidth(bb), # aesthetic for big plots
        .05 * boxheight(bb), # aesthetic for big plots
    )
    return padding + boxwidth(bb), padding + boxheight(bb)
end