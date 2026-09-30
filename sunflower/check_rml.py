"""Structural checks on this project's generated RML -- see ../plantgen/check_rml.py.

    python3 check_rml.py
"""
import os, runpy, sys

here = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], here]
runpy.run_path(os.path.join(here, "..", "plantgen", "check_rml.py"), run_name="__main__")
