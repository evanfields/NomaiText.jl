"""Whether two lines cross in their interiors. Touching endpoints or crossing when the
lines are extended to infinity do not count."""
function _linescross(ptA, ptB, ptC, ptD)
    crosses, pt = intersectionlines(ptA, ptB, ptC, ptD; crossingonly = true)
    # if they don't cross, no nee dto check the crossing point
    !crosses && return false
    # if the crossing point is one of the endpoints, we count it as not crossing
    return pt ∉ (ptA, ptB, ptC, ptD)
end

"Whether the line `(ptA, ptB)` crosses any line in `ps`."
function intersects(ps::PolySpec, ptA::Point, ptB::Point)
    length(ps.points) < 2 && return false
    n_ps = length(ps.points)
    @inbounds for i in 1:(n_ps - 1)
        if _linescross(ptA, ptB, ps.points[i], ps.points[i+1])
            return true
        end
    end
    # only need to check the end => start edge if the poly is closed
    if ps.close
        return _linescross(ptA, ptB, ps.points[end], ps.points[1])
    else # no poly edges left to check, so no intersection
        return false
    end
end
intersects(ptA::Point, ptB::Point, ::Nothing) = false

"""
    intersects(psA, psB, offset::Point)

Whether two polygons defined by `psA` and `psB` intersect when `psB` is offset by `offset`.
If either of `psA` or `psB` is nothing, the return false since there's no intersection."""
function intersects(psA::PolySpec, psB::PolySpec, offset::Point)
    length(psB.points) < 2 && return false
    n_b = length(psB.points)
    @inbounds for i in 1:(n_b - 1)
        if intersects(psA, psB.points[i] + offset, psB.points[i+1] + offset)
            return true
        end
    end
    # only need to check the end => start edge if psB is closed
    if psB.close
        return intersects(psA, psB.points[end] + offset, psB.points[1] + offset)
    else # no psB edges left to check, so no intersection
        return false
    end
end
intersects(psA::PolySpec, ::Nothing, ::Point) = false
intersects(::Nothing, psB::PolySpec, ::Point) = false
intersects(::Nothing, ::Nothing, ::Point) = false

"""Compute whether two Glyphs cross when `glyphB` is offset by `off`."""
function intersects(glyphA::Glyph, glyphB::Glyph, off::Point)
    return (
        intersects(glyphA.core, glyphB.core, off) ||
        intersects(glyphA.core, glyphB.annotation, off) ||
        intersects(glyphA.annotation, glyphB.core, off) ||
        intersects(glyphA.annotation, glyphB.annotation, off)
    )
end


##
# "Missing" Luxor utilities for manipulating stored paths
##

"""Given a stored path `p``, return a new stored path equivalent to rotating `p` by
`theta` radians around the origin. Follows standard Luxor rotation logic."""
function rotatepath(p::Path, theta)
    return Path(_rotate_path_el.(p.path, theta))
end

_rotate_path_el(pc::PathClose, theta) = pc
_rotate_path_el(pl::PathLine, theta) = PathLine(rotatepoint(pl.pt1, O, theta))
_rotate_path_el(pm::PathMove, theta) = PathMove(rotatepoint(pm.pt1, O, theta))
function _rotate_path_el(pc::PathCurve, theta)
    pts = rotatepoint.((pc.pt1, pc.pt2, pc.pt3), theta)
    return PathCurve(pts...)
end
