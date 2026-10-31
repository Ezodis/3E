# SPDX-License-Identifier: MIT
from functools import partial
import json
import os
import sys
import time
from ableton.v2.control_surface import ControlSurface, MIDI_CC_TYPE, MIDI_NOTE_TYPE
from ableton.v2.control_surface.elements import ButtonElement, SliderElement
from .mapping import Mapping, CONTROL_CHANNEL, CCS, NOTES


class PhoneBar(ControlSurface):
    def __init__(self, *args, **kwargs):
        super(PhoneBar, self).__init__(*args, **kwargs)
        self._phone_mapping = Mapping(self.song, self.show_message)
        self._phone_controls = []
        self._feedback_at = 0
        base = os.path.expanduser('~/Library/Application Support') if sys.platform == 'darwin' else os.getenv('LOCALAPPDATA', os.path.expanduser('~'))
        self._feedback_path = os.path.join(base, '3E', 'phone-live.json')
        with self.component_guard():
            for number in CCS:
                control = SliderElement(MIDI_CC_TYPE, CONTROL_CHANNEL, number, name='Phone_CC_%d' % number)
                control.add_value_listener(partial(self._handle, False, number))
                self._phone_controls.append(control)
            for number in NOTES:
                control = ButtonElement(True, MIDI_NOTE_TYPE, CONTROL_CHANNEL, number, name='Phone_Note_%d' % number)
                control.add_value_listener(partial(self._handle, True, number))
                self._phone_controls.append(control)
        self.log_message('3E Phone Bar ready: controls on channel 16; piano on channels 1–15')
        self.show_message('3E Phone Bar connected — mixer tracks 1–8, decks tracks 1–2')

    def _handle(self, note, number, value):
        try:
            self._phone_mapping.receive(note, number, value)
        except (RuntimeError, AttributeError, IndexError) as error:
            # A track/device may disappear during a gesture or Set change.
            self.log_message('3E Phone Bar: %s' % error)

    def update_display(self):
        super(PhoneBar, self).update_display()
        now = time.time()
        if now - self._feedback_at < .25:
            return
        self._feedback_at = now
        try:
            snapshot = self._phone_mapping.snapshot()
            snapshot['updated'] = now
            directory = os.path.dirname(self._feedback_path)
            if not os.path.isdir(directory):
                os.makedirs(directory)
            temporary = self._feedback_path + '.tmp'
            with open(temporary, 'w') as output:
                json.dump(snapshot, output, separators=(',', ':'))
            os.replace(temporary, self._feedback_path)
        except (OSError, RuntimeError, AttributeError, ValueError):
            pass
