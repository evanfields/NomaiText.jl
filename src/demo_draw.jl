using Colors
function demo_draw(gl::AbstractGridLayout, as_string = false)
    width, height = drawing_size(gl)
    pic = @drawsvg begin
        # style
        setline(4)
        background("antiquewhite")
        setlinecap(:round)
        setlinejoin(:round)
        # draw the path
        @layer begin
            setcolor(colorant"grey27")
            newpath()
            origin()
            translate(-midpoint(pgl.bounding_box))
            setline(8)
            drawpath(gl.path, action = :stroke)
        end
        # draw the glyph locations themselves
        colors = [
            colorant"#104e8b", # dodgerblue4
            colorant"#90271a", # redish
            colorant"#005d2c", # greenish
        ]
        grid_size = size(gl.grid.grid)
        for i in 1:grid_size[1], j in 1:grid_size[2]
            origin()
            transform(gl, i, j)
            @layer begin
                setcolor(colors[j])
                circle(O, K/1.5, :fill)
            end
        end
    end width height
    as_string && return svgstring()
    return pic
end
pgl = nothing
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
function demo_spiral(
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
    period = pi/4
    Drawing(100, 100, :svg) # needed so we can draw spirals and get their lengths
    while true
        newpath()
        spiral(164, .29, log = true, action = :path, period = period)
        spath = storepath()
        pathlength(spath) >= needed_length && break
        period += pi/24
    end
    newpath()
    rotation_needed = pi - mod(period, 2pi)
    spath = rotatepath(spath, rotation_needed)
    global pgl = PathGridLayout(grid, spath)
    demo_draw(PathGridLayout(grid, spath), as_string)
end