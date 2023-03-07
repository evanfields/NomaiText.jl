using Random: default_rng


"""
    handwrite(g::Glyph, h::Real, [point_map, [rng]])

Return a copy of a Glyph with points perturbed a la handwriting. Parameter `h >= 0`
controls the perturbation amount. `h = 0` means no perturbation, `h = 1` roughly
corresponds to "normal" handwriting, `h = 2` could be a child's writing, and larger
`h` further degrade the glyph. Note that perturbations are applied to each point
independently, so handwriting can alter glyph topology by creating crossings.

Optionally pass a `point_map` which will be used to lookup any existing point
transforms and record new point transforms. Optionally pass a RNG."""
function handwrite(
    g::Glyph,
    h::Real,
    point_map = Dict{Point, Point}(),
    rng = default_rng()
)
    # Unlike most Glyph operations, we can't operate on the core and annotation separately;
    # they may share points which need to be transformed the same way.
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

"""Handwrite a GlyphGrid. Returns a modified copy.
TODO: add more docstring."""
function handwrite(gg::GlyphGrid, h::Real, rng = default_rng())
    gg = deepcopy(gg)
    # record a different point map for each glyph
    # (different glyphs may share the same points, since glyphs are roughly 0-centered)
    point_maps = [Dict{Point, Point}() for _ in gg.grid]
    # update each glyph with its own point_map
    for ind in CartesianIndices(gg.grid)
        !hasglyph(gg.grid[ind]) && continue
        gg.grid[ind] = handwrite(gg.grid[ind], h, point_maps[ind], rng)
    end
    # update each connection by referring back to glyph-wise point_maps
    gg.connections = map(gg.connections) do conn
        new_pt1 = point_maps[conn.coord1...][conn.point1]
        new_pt2 = point_maps[conn.coord2...][conn.point2]
        return GlyphConnection(
            conn.coord1,
            new_pt1,
            conn.coord2,
            new_pt2
        )
    end
    return gg
end
