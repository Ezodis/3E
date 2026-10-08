from .miditouchbar import MidiTouchbar
from .strip3_record import RecordServer


class Strip3MidiTouchbar(MidiTouchbar):
    def __init__(self, *args, **kwargs):
        self._strip3_record = None
        super(Strip3MidiTouchbar, self).__init__(*args, **kwargs)
        self._strip3_record = RecordServer(self.song)

    def update_display(self):
        super(Strip3MidiTouchbar, self).update_display()
        if self._strip3_record is not None:
            try:
                self._strip3_record.poll()
            except Exception as error:
                self.log_message("Strip3 Record: %s" % error)

    def disconnect(self):
        if self._strip3_record is not None:
            self._strip3_record.close()
            self._strip3_record = None
        super(Strip3MidiTouchbar, self).disconnect()
