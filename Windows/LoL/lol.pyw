#! python3.12
"""Windowless launcher for lol.py (3£'s "LoL macros" toggle runs this file).
The line above makes the py launcher use Python 3.12, where the packages are installed
(it would otherwise pick the newest Python, 3.14, which doesn't have them).

.pyw files run with pythonw, so no console window appears.
"""
import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)
sys.path.insert(0, here)
runpy.run_path(os.path.join(here, "lol.py"), run_name="__main__")
