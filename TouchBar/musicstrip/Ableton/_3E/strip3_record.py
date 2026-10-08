"""Strip3 Record: local, acknowledged commands on Live's control-surface thread.

No keyboard emulation, Accessibility prompts, or guessing at UI button names.
The original MIDITouchbar device/parameter implementation is unchanged.
"""
import fcntl
import json
import math
import os
import time
import uuid

ROOT = os.path.expanduser("~/Library/Application Support/Strip3/AbletonRecord")
TOGGLES = {"record": "record_mode", "session": "session_record",
           "punch-in": "punch_in", "punch-out": "punch_out",
           "overdub": "arrangement_overdub", "loop": "loop",
           "click": "metronome", "automation-arm": "session_automation_record"}


class RecordServer:
    def __init__(self, song, root=ROOT, clock=time.time):
        self.song, self.root, self.clock = song, root, clock
        self.session = str(uuid.uuid4())
        self.last_id, self.error = "", ""
        os.makedirs(root, mode=0o700, exist_ok=True)
        self.commands = os.path.join(root, "commands")
        self.responses = os.path.join(root, "responses")
        os.makedirs(self.commands, mode=0o700, exist_ok=True)
        os.makedirs(self.responses, mode=0o700, exist_ok=True)
        self.lock = open(os.path.join(root, "server.lock"), "a")
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.active = True
        except BlockingIOError:
            self.active = False
        if self.active:
            self.publish()

    def selected_index(self):
        selected = self.song.view.selected_track
        return next((i for i, track in enumerate(self.song.tracks)
                     if track == selected), -1)

    def state(self):
        track = self.song.view.selected_track
        result = {"protocol": 1, "pid": os.getpid(), "session_id": self.session,
                  "time": self.clock(), "track_index": self.selected_index(),
                  "track_name": str(track.name), "can_arm": bool(track.can_be_armed),
                  "armed": bool(track.arm) if track.can_be_armed else False,
                  "last_id": self.last_id, "error": self.error}
        result.update({key: bool(getattr(self.song, prop))
                       for key, prop in TOGGLES.items()})
        result["quantization"] = int(self.song.midi_recording_quantization)
        result.update(performance=1, playing=bool(self.song.is_playing),
                      tempo=float(self.song.tempo), loop_start=float(self.song.loop_start),
                      loop_length=float(self.song.loop_length),
                      beats_per_bar=self.song.signature_numerator * 4.0 / self.song.signature_denominator)
        intervals = list(getattr(self.song, "scale_intervals", ()))
        result.update(scale_supported=bool(intervals),
                      scale_mode=bool(getattr(self.song, "scale_mode", False)),
                      root_note=int(getattr(self.song, "root_note", 0)),
                      scale_name=str(getattr(self.song, "scale_name", "")),
                      scale_intervals=intervals)
        return result

    def atomic_json(self, path, payload):
        temporary = path + ".tmp"
        with open(temporary, "w") as output:
            json.dump(payload, output)
        os.replace(temporary, path)

    def publish(self):
        self.atomic_json(os.path.join(self.root, "state.json"), self.state())

    def execute(self, command):
        age = self.clock() - float(command.get("time", 0))
        if command.get("session") != self.session or age < -1 or age > 2:
            raise ValueError("Expired Live command; try again")
        action = command.get("action")
        if action in TOGGLES:
            prop = TOGGLES[action]
            setattr(self.song, prop, not getattr(self.song, prop))
        elif action == "play":
            if self.song.is_playing:
                self.song.stop_playing()
            else:
                self.song.continue_playing()
        elif action == "stop":
            self.song.stop_playing()
        elif action == "tap-tempo":
            self.song.tap_tempo()
        elif action == "session-capture":
            self.song.trigger_session_record()
        elif action in ("tempo-up", "tempo-down", "tempo-up-fine", "tempo-down-fine"):
            delta = 0.1 if action.endswith("fine") else 1.0
            if "down" in action:
                delta = -delta
            self.song.tempo = max(20.0, min(999.0, round(self.song.tempo + delta, 2)))
        elif action in ("loop-1", "loop-2", "loop-4", "loop-8"):
            beats = self.song.signature_numerator * 4.0 / self.song.signature_denominator
            self.song.loop_start = max(0.0, math.floor(self.song.current_song_time / beats) * beats)
            self.song.loop_length = beats * int(action.rsplit("-", 1)[1])
            self.song.loop = True
        elif action in ("loop-half", "loop-double"):
            beats = self.song.signature_numerator * 4.0 / self.song.signature_denominator
            factor = 0.5 if action == "loop-half" else 2.0
            self.song.loop_length = max(beats / 4.0, min(beats * 128, self.song.loop_length * factor))
        elif action in ("loop-prev", "loop-next"):
            direction = -1 if action == "loop-prev" else 1
            self.song.loop_start = max(0.0, self.song.loop_start + direction * self.song.loop_length)
        elif action == "stop-clips":
            self.song.stop_all_clips()  # Use Live's launch quantization, not an abrupt cut.
        elif action == "re-enable-automation":
            self.song.re_enable_automation()
        elif action in ("arm-on", "arm-off"):
            track = self.song.view.selected_track
            if command.get("track_index") != self.selected_index():
                raise ValueError("Selected track changed; swipe again")
            if not track.can_be_armed:
                raise ValueError("Select an audio or MIDI track")
            desired = action == "arm-on"
            # Touch Bar swipes are additive, like modifier-clicking Arm.
            # Do not implement Live's exclusive-arm UI preference here.
            track.arm = desired  # Explicit state: repeated swipes never toggle.
        elif action == "quantization":
            values = (0, 2, 5)  # None, eighth, sixteenth; Live Record Quantization.
            current = int(self.song.midi_recording_quantization)
            index = values.index(current) if current in values else -1
            self.song.midi_recording_quantization = values[(index + 1) % len(values)]
        else:
            raise ValueError("Unknown Record command")

    def poll(self):
        if not self.active:
            return
        for name in sorted(os.listdir(self.commands))[:32]:
            if not name.endswith(".json"):
                continue
            token = name[:-5]
            try:
                if str(uuid.UUID(token)) != token:
                    continue
                path = os.path.join(self.commands, name)
                with open(path) as source:
                    command = json.load(source)
                os.unlink(path)  # Consume before acting; never replay a toggle.
                self.last_id, self.error = token, ""
                try:
                    self.execute(command)
                except Exception as error:
                    self.error = str(error)
                self.atomic_json(os.path.join(self.responses, name),
                                 {"ok": not bool(self.error), "error": self.error,
                                  "state": self.state()})
            except (OSError, ValueError):
                continue
        self.publish()
        # Responses are disposable acknowledgements, not app backups.
        for name in os.listdir(self.responses):
            path = os.path.join(self.responses, name)
            try:
                if self.clock() - os.path.getmtime(path) > 30:
                    os.unlink(path)
            except OSError:
                pass

    def close(self):
        if self.active:
            self.active = False
            try:
                path = os.path.join(self.root, "state.json")
                with open(path) as source:
                    own_state = json.load(source).get("session_id") == self.session
                if own_state:
                    os.unlink(path)
            except (OSError, ValueError):
                pass
        self.lock.close()
