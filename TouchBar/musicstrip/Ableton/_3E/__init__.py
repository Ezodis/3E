from __future__ import absolute_import, print_function, unicode_literals
from .strip3 import Strip3MidiTouchbar

def create_instance(c_instance):
    return Strip3MidiTouchbar(c_instance=c_instance)
