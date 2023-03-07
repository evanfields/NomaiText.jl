using Random: default_rng


"""
    handwrite(g::Glyph, h::Real, [rng])

Return a copy of a Glyph with points perturbed a la handwriting. Parameter `h >= 0`
controls the perturbation amount. `h = 0` means no perturbation, `h = 1` roughly
corresponds to "normal" handwriting, `h = 2` could be a child's writing, and larger
`h` further degrade the glyph. Note that perturbations are applied to each point
independently, so handwriting can alter glyph topology by creating crossings."""
function handwrite(g::Glyph, h::Real, rng = default_rng())
    # Unlike most Glyph operations, we can't operate on the core and annotation separately;
    # they may share points which need to be transformed the same way.
    point_map = Dict{Point, Point}()
    return Glyph(
        handwrite(g.core, h, point_map, rng),
        isnothing(g.annotation) ? nothing : handwrite(g.annotation, h, point_map, rng)
    )
end
"""Handwrite a PolySpec, using `point_map` to lookup any existing point transforms and
record new point transforms. Returns a new `PolySpec` object while modifying `point_map`
in place."""
function handwrite(ps::PolySpec, h::Real, point_map, rng = default_rng())
    translation = K * h / 8 * Point(randn(rng), randn(rng)) # glyph shift
    new_points = map(ps.points) do pt
        haskey(point_map, pt) && return point_map[pt]
        new_pt = pt + K * h / 20 * Point(randn(rng), randn(rng)) + translation
        point_map[pt] = new_pt
        return new_pt
    end
    return PolySpec(
        new_points,
        ps.close
    )
end