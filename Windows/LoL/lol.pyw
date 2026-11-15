#! python3.12
"""Windowless launcher for lol.py (3£'s "LoL macros" toggle runs this file).
The line above makes the py launcher use Python 3.12, where the packages are installed
(it would otherwise pick the newest Python, 3.14, which doesn't have them).

.pyw files run with pythonw, so no console window appears.
"""
import os
import runpy
import sys
import logging
from logging.handlers import RotatingFileHandler
import threading

data = os.path.join(os.environ["LOCALAPPDATA"], "3EWindows", "LoL")
os.makedirs(data, exist_ok=True)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                    handlers=[RotatingFileHandler(os.path.join(data, "lol_runtime.log"),
                              maxBytes=2_000_000, backupCount=2, encoding="utf-8")])


class LogStream:
    def write(self, text):
        if text.strip():
            logging.warning(text.rstrip())

    def flush(self):
        pass


sys.stdout = sys.stderr = LogStream()
sys.excepthook = lambda kind, value, tb: logging.critical(
    "Macro launcher failed", exc_info=(kind, value, tb))
threading.excepthook = lambda args: logging.error(
    "Macro thread failed: %s", args.thread.name,
    exc_info=(args.exc_type, args.exc_value, args.exc_traceback))

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)
sys.path.insert(0, here)
runpy.run_path(os.path.join(here, "lol.py"), run_name="__main__")
