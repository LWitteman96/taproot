"""Checks on this project's *built* file -- see ../plantgen/check_built.py.

    python3 check_built.py
"""
import os, runpy, sys

here = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], here]
runpy.run_path(os.path.join(here, "..", "plantgen", "check_built.py"), run_name="__main__")
