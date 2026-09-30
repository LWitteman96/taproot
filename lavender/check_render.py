"""Prove the data drives this project's render -- see ../plantgen/check_render.py.

    python3 check_render.py
"""
import os, runpy, sys

here = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], here]
runpy.run_path(os.path.join(here, "..", "plantgen", "check_render.py"), run_name="__main__")
