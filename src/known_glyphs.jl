# all the glyphs we wish to draw
const KNOWN_GLYPHS = Glyph[]

#=
Note: this file refers frequently to the core glyphs defined in digit_shapes.jl.
When reading this file, you'll probably want to refer there simultaneously.
=#

##
# Step 1: all core glyphs are known
##
for ct in CORE_GLYPH_TYPES
    push!(KNOWN_GLYPHS, core_glyph(ct))
end

##
# Step 2: annotations with single squares - mostly hex glyphs
##
"""Compute the square which has edge `(ptA, ptB)` and "turns left" after going A -> B."""
function _compute_square(ptA, ptB)
	ptC = rotatepoint(ptA, ptB, pi/2)
	ptD = rotatepoint(ptB, ptA, -pi/2)
	return PolySpec([ptA, ptB, ptC, ptD], true)
end
# glyph digit 3 can have another square above
let g = core_glyph(GlyphDigit3)
    square = _compute_square(g.core.points[3], g.core.points[4])
    push!(KNOWN_GLYPHS, .7 * Glyph(g.core, square))
end
# glyph digit 7 can have a square on the upper right
let g = core_glyph(GlyphDigit7)
    square = _compute_square(g.core.points[3], g.core.points[4])
    push!(KNOWN_GLYPHS, .9 * Glyph(g.core, square))
end
# glyph digit 9 can have a square on the bottom right
let g = core_glyph(GlyphDigit9)
    square = _compute_square(g.core.points[1], g.core.points[2])
    push!(KNOWN_GLYPHS, .9 * Glyph(g.core, square))
end
# glyph digit 10 can have a square on the upper right
let g = core_glyph(GlyphDigit10)
    square = _compute_square(g.core.points[4], g.core.points[5])
    push!(KNOWN_GLYPHS, .9 * Glyph(g.core, square))
end
# glyph digit 11 can have a square on the bottom right
let g = core_glyph(GlyphDigit11)
    square = _compute_square(g.core.points[1], g.core.points[2])
    push!(KNOWN_GLYPHS, .9 * Glyph(g.core, square))
end
# glyph digit 15 can have a square on the bottom right
let g = core_glyph(GlyphDigit15)
    square = _compute_square(g.core.points[6], g.core.points[1])
    push!(KNOWN_GLYPHS, .9 * Glyph(g.core, square))
end

##
# Step 3: lots of glyphs get a single-edge spike
##
"""Compute the terminal point of a single-edge spike starting at `ptB` with length `len`
that bisects the angle on the left as you move A -> B -> C.
Used for placing spikes, hooks, and horns."""
function _compute_spike_pt(ptA, ptB, ptC, len)
    full_angle = anglethreepoints(ptC, ptB, ptA)
    rotate_angle = full_angle / 2
    # find the point on the line B - A which is len away from B
    dist = distance(ptA, ptB)
    return rotatepoint(
        ptB + ((ptA - ptB) * len / dist),
        ptB,
        rotate_angle
    )
end
"""Compute the single-edge spike at `ptB` with length `len` that bisects the angle on the
left at B as you move A -> B -> C."""
function _compute_spike(ptA, ptB, ptC, len = 3K/4)
    return PolySpec([ptB, _compute_spike_pt(ptA, ptB, ptC, len)], false)
end
# glyph digit 0 can have a spike to the upper right
let g = core_glyph(GlyphDigit0)
    spike = _compute_spike(g.core.points[2:4]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, spike))
end
# glyph digit 1 can have a spike to the lower left
let g = core_glyph(GlyphDigit1)
    spike = _compute_spike(g.core.points[1:3]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, spike))
end
# glyph digit 2 can have a spike to the lower left
let g = core_glyph(GlyphDigit2)
    spike = _compute_spike(g.core.points[2:4]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, spike))
end
# glyph digit 4 (pentagon) can have a spike to the top
let g = core_glyph(GlyphDigit4)
    spike = _compute_spike(g.core.points[3:5]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, spike))
end
# glyph digit 4 (pentagon) can have a spike to the bottom
let g = core_glyph(GlyphDigit4)
    spike = _compute_spike(g.core.points[[5,1,2]]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, spike))
end
# glyph digit 4 (pentagon) can have a spike to the right
let g = core_glyph(GlyphDigit4)
    spike = _compute_spike(g.core.points[[4,5,1]]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, spike))
end

##
# Step 4: horns
##
"""Compute the two-spike "horns" with length `len` for edge B => C. Horns are on the left
as you move A -> B -> C -> D."""
function _compute_horns(ptA, ptB, ptC, ptD, len = .75 * K)
    start = _compute_spike_pt(ptA, ptB, ptC, len)
    stop = _compute_spike_pt(ptB, ptC, ptD, len)
    return PolySpec([start, ptB, ptC, stop], false)
end
# glyph digit 0 can have upper horns
let g = core_glyph(GlyphDigit0)
    horns = _compute_horns(g.core.points...)
    push!(KNOWN_GLYPHS, Glyph(g.core, horns))
end
# glyph digit 1 can have left horns
let g = core_glyph(GlyphDigit1)
    horns = _compute_horns(g.core.points...)
    push!(KNOWN_GLYPHS, Glyph(g.core, horns))
end
# glyph digit 2 can have lower horns
let g = core_glyph(GlyphDigit2)
    horns = _compute_horns(g.core.points...)
    push!(KNOWN_GLYPHS, Glyph(g.core, horns))
end
# glyph digit 3 can have right horns
let g = core_glyph(GlyphDigit3)
    horns = _compute_horns(g.core.points[[3,4,1,2]]...)
    push!(KNOWN_GLYPHS, Glyph(g.core, horns))
end

##
# Step final: one-off special funsies
##
# digit 15 (full hex) can have a pentagon to the right
let g = core_glyph(GlyphDigit15)
    pent_pts = ngonside(O, K, 5; vertices = true)
    min_x = minimum(pt.x for pt in pent_pts)
    pent = PolySpec(
        pent_pts .+ Point(K * sqrt(3) / 2 - min_x, 0), # align with right edge of hex
        true
    )
    push!(KNOWN_GLYPHS, .65 * Glyph(g.core, pent))
end