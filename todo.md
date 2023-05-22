1. Write a new `GlyphGrid` which combines the best of both versions:
    * the original (see commit `b2bff2566b` or previous) has a nice coils-back-on-itself
    structure, but maybe folds back too densely so that especially near boundaries
    every possibly glyph location in the grid is taken.
    * the current (`glyphgrid2.jl` in older commits) has a nice multiple-path structure
    but could be denser and coil back more.
2. Take another stab at linear layouts, right now they don't seem better than just
using a strict grid layout. Maybe try varying glyph size a bit?
3. Fix some more edge cases of glyph overlap.
    * This probably requires a fully general computation in `geometry.jl` of whether
    two glyphs with different transforms overlap.
    * Then a spiral layout could pack glyphs more densely without suffering overlap.
4. Modify the mapping of `String => Oracle => GlyphGrid` so that the eventual
    grid is only locally sensitive to input changes, not globally sensitive. For example,
    maybe each word contributes independently to the eventual Nomai text, so that
    `"abc def"` and `"abc xyz"` have the same initial glyphs. One idea for how to do this:
    * Define a `MetaOracle` with the same interface (`ask!`, etc.) as an `Oracle`. Each
    `MetaOracle` wraps a sequence of one or more `Oracles` and exhausts them one by one.
    * Split input strings on whitespace and generate an `Oracle` for each word, then
    combine these into a `MetaOracle`.
    * When building a `GlyphGrid` from a `MetaOracle`, have a special sentinel glyph
    at the start of each word in the same row on the grid. After an individual
    `Oracle` in a `MetaOracle` is exhausted, the place the next sentinel glyph
    and have the existing paths join at that new sentinel. Then the next word can
    begin from a fixed glyph (the sentinel) at a fixed position (row), so changes
    to one word in the input message won't affect the rest of the embedding.
5. Somewhat relatedly, generate special sentinel glyphs when an `Oracle` is exhausted so
    that we can distinguish between an `Oracle` wrapping back on itself and a longer
    `Oracle` with the same sequence of initial answers. E.g. two `Oracles` that respond to
    which-of-three questions respectively `(2,1,3)` and `(2,1,3,2)` will look the same if
    ask exactly 4 questions. This means in rare cases distinct messages can have the same
    spiral when an `Oracle` needs to loop back on itself to complete a glyph that another
    similar `Oracle` can complete exactly.
6. Re-enable server functionality (see commit `b2bff2566b`) with a package extension.
We don't need it as a full dependency, especially for use on AWS Lambda.
7. More glyphs and/or annotations?
8. Refactor so that core glyph digits aren't in the type system? This stemmed from an
    earlier design which didn't end up materializing. Or use the type system more so
    that we actually benefit from dispatch. As-is, we could just have an array of
    core glyph digits without defining any types.
9. Probably write some tests, we should be adults after all...
