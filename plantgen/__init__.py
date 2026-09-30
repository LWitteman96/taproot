"""plantgen -- the shared half of every Taproot plant generator.

    geometry.py   the drawable model (Contour, Path, Group ...) and its helpers
    ground.py     the soil every plant stands in
    roots.py      root trees, grown between levels by scale
    svg.py        the SVG writer
    rml.py        the RML emitter
    species.py    a plant as a Rive project: stages, roots, view model, wiring

A plant generator (fern/fern_generator.py, oak/oak_generator.py) supplies its
own art and motion tables and hands them to species.Species. The conventions
and traps behind all of this are written up in fern/NOTES.md.
"""
