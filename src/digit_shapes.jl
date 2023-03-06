using Luxor


function _core_poly end
let # square glyphs 0-3
    r = sqrt(2) * K/2
    pts = polar.(r, [pi/4 + pi/2 * i for i in 0:3]) # bottom right CW, as in
    # 3 4
    # 2 1
    
    NomaiText._core_poly(::Type{GlyphDigit0}) = PolySpec(
        [pts[2], pts[3], pts[4], pts[1]],
        false
    )
    NomaiText._core_poly(::Type{GlyphDigit1}) = PolySpec(deepcopy(pts), false)
    NomaiText._core_poly(::Type{GlyphDigit2}) = PolySpec(pts[[4,1,2,3]], false)
    NomaiText._core_poly(::Type{GlyphDigit3}) = PolySpec(deepcopy(pts), true)
end
let # pentagon glyph 4
    rad = sqrt(.5 + sqrt(5) / 10) * K
    pts = ngon(O, rad, 5; vertices = true) # CW from bottom point
    NomaiText._core_poly(::Type{GlyphDigit4}) = PolySpec(deepcopy(pts), true)
end
let # hexagons 5-15
    pts = ngon(O, K, 6, pi/6; vertices = true) # CW from bottom
    NomaiText._core_poly(::Type{GlyphDigit5}) = PolySpec(pts[2:4], false)
    NomaiText._core_poly(::Type{GlyphDigit6}) = PolySpec(pts[1:3], false)
    NomaiText._core_poly(::Type{GlyphDigit7}) = PolySpec(pts[2:5], false)
    NomaiText._core_poly(::Type{GlyphDigit8}) = PolySpec(pts[1:4], false)
    NomaiText._core_poly(::Type{GlyphDigit9}) = PolySpec(pts[[6,1,2,3]], false)
    NomaiText._core_poly(::Type{GlyphDigit10}) = PolySpec(pts[1:5], false)
    NomaiText._core_poly(::Type{GlyphDigit11}) = PolySpec(pts[[6,1,2,3,4]], false)
    NomaiText._core_poly(::Type{GlyphDigit12}) = PolySpec(deepcopy(pts), false)
    NomaiText._core_poly(::Type{GlyphDigit13}) = PolySpec(pts[[6,1,2,3,4,5]], false)
    NomaiText._core_poly(::Type{GlyphDigit14}) = PolySpec(pts[[5,6,1,2,3,4]], false)
    NomaiText._core_poly(::Type{GlyphDigit15}) = PolySpec(deepcopy(pts), true)
end