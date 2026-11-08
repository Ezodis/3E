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

    def selected_arm_targets(self):
        """Return Live's complete selected-track set when the version exposes it."""
        view = self.song.view
        for name in ("selected_tracks", "selected_track_set"):
            try:
                selected = getattr(view, name, None)
                if selected:
                    tracks = list(selected)
                    if tracks:
                        return [track for track in tracks
                                if getattr(track, "can_be_armed", False)]
            except (AttributeError, TypeError, RuntimeError):
                pass
        # A few Live builds expose selection on each Track/Track.View even
        # though it is absent from the documented Song.View surface.
        tracks = list(getattr(self.song, "tracks", ()))
        selected = []
        for track in tracks:
            for owner in (track, getattr(track, "view", None)):
                if owner is None:
                    continue
                for name in ("is_selected", "selected"):
                    try:
                        if bool(getattr(owner, name, False)):
                            selected.append(track)
                            break
                    except (AttributeError, RuntimeError):
                        pass
                else:
                    continue
                break
        if selected:
            return [track for track in selected
                    if getattr(track, "can_be_armed", False)]
        track = view.selected_track
        return [track] if getattr(track, "can_be_armed", False) else []

    def arm_selection_source(self):
        for name in ("selected_tracks", "selected_track_set"):
            try:
                selected = getattr(self.song.view, name, None)
                if selected and list(selected):
                    return name
            except (AttributeError, TypeError, RuntimeError):
                pass
        for track in getattr(self.song, "tracks", ()):
            for owner in (track, getattr(track, "view", None)):
                if owner is None:
                    continue
                for name in ("is_selected", "selected"):
                    try:
                        if bool(getattr(owner, name, False)):
                            return "track." + name
                    except (AttributeError, RuntimeError):
                        pass
        return "selected_track"

    @staticmethod
    def chain_selector(device):
        return next((p for p in getattr(device, "parameters", ())
                     if getattr(p, "original_name", p.name) == "Chain Selector"), None)

    def song_banks(self):
        return [(track, device, self.chain_selector(device))
                for track in self.song.tracks
                for device in getattr(track, "devices", ())
                if str(device.name) == "SONG: 0 DIABLA | 1 RUFF | 2 NOTA"
                and self.chain_selector(device) is not None
                and len(getattr(device, "chains", ())) == 3]

    def active_piano_devices(self, track):
        for device in getattr(track, "devices", ()):
            if str(device.name) == "SONG: 0 DIABLA | 1 RUFF | 2 NOTA":
                selector = self.chain_selector(device)
                chains = getattr(device, "chains", ())
                index = int(selector.value) if selector else -1
                if 0 <= index < len(chains):
                    yield from getattr(chains[index], "devices", ())
            else:
                yield device

    def bind_song_loop_sounds(self):
        """Native clip automation keeps saved loops paired with their sound bank."""
        count = 0
        for track, device, selector in self.song_banks():
            if "MIDI LOOPS" not in str(track.name):
                continue
            for slot in getattr(track, "clip_slots", ()):
                clip = slot.clip if slot.has_clip else None
                if clip is None or clip.is_recording:
                    continue
                name = str(clip.name).split(" - ", 1)[0]
                if name not in ("DIABLA", "RUFF", "NOTA"):
                    continue
                envelope = clip.automation_envelope(selector)
                if envelope is None:
                    envelope = clip.create_automation_envelope(selector)
                    envelope.insert_step(clip.loop_start, clip.loop_end - clip.loop_start,
                                         ("DIABLA", "RUFF", "NOTA").index(name))
                count += 1
        if not count:
            raise ValueError("No song-library loops found")

    def select_song_preset(self, action):
        if action == "song-bind-loops":
            self.bind_song_loop_sounds()
            return
        presets = {"song-diabla": (0, 84, 10, "Minor", "DIABLA"),
                   "song-ruff": (1, 108, 1, "Major", "RUFF"),
                   "song-nota": (2, 94, 2, "Minor", "NOTA")}
        if action not in presets:
            raise ValueError("Unknown song preset")
        banks = self.song_banks()
        if len(banks) < 2:
            raise ValueError("Open the song-library template first")
        if self.song.record_mode or self.song.session_record:
            raise ValueError("Finish recording before switching song sounds")
        index, tempo, root, scale, name = presets[action]
        self.song.begin_undo_step()
        try:
            self.song.stop_all_clips()
            for track, device, selector in banks:
                selector.value = index
            self.song.tempo = tempo
            scene = next((scene for scene in getattr(self.song, "scenes", ())
                          if str(scene.name) == name + " - Base"), None)
            if scene is not None:
                self.song.view.selected_scene = scene
                scene_index = list(self.song.scenes).index(scene)
                # A previously selected song clip can restore its scale after
                # this command. Focus the live piano's empty slot first.
                piano = next((track for track in self.song.tracks
                              if str(track.name).startswith("P2 CHORDS")), None)
                slots = getattr(piano, "clip_slots", ())
                if scene_index < len(slots):
                    self.song.view.selected_track = piano
                    self.song.view.highlighted_clip_slot = slots[scene_index]
            self.song.root_note = root
            self.song.scale_name = scale
            self.song.scale_mode = True
        finally:
            self.song.end_undo_step()

    def piano_modes(self):
        """Only expose explicit mode racks on unambiguous named piano tracks."""
        found = {}
        for track in self.song.tracks:
            prefix = str(track.name).split(" ", 1)[0]
            if prefix not in ("P1", "P2", "P3"):
                continue
            for device in self.active_piano_devices(track):
                if not str(device.name).startswith("MODE: 0 Plain | 1 Arp | 2 Bounce"):
                    continue
                parameter = next((p for p in device.parameters
                                  if getattr(p, "original_name", p.name) == "Chain Selector"), None)
                if parameter is not None:
                    channel = prefix[1:]
                    if channel in found:
                        # Ambiguous duplicated tracks must not control an arbitrary rack.
                        found[channel] = None
                    else:
                        found[channel] = parameter
        return {channel: parameter for channel, parameter in found.items() if parameter is not None}

    def piano_mode_labels(self):
        modes = self.piano_modes()
        labels = {channel: ["Chord", "Arpeggio", "Bounce"] for channel in modes}
        for track in self.song.tracks:
            channel = str(track.name).split(" ", 1)[0][1:]
            if channel not in modes:
                continue
            for device in self.active_piano_devices(track):
                if self.chain_selector(device) != modes[channel]:
                    continue
                for extra in ("RUFF", "NOTA"):
                    if str(device.name) == "MODE: 0 Plain | 1 Arp | 2 Bounce | 3 " + extra:
                        labels[channel].append(extra)
        return labels

    def clip_context(self):
        slot = getattr(self.song.view, "highlighted_clip_slot", None)
        for ti, track in enumerate(self.song.tracks):
            for si, candidate in enumerate(getattr(track, "clip_slots", ())):
                if candidate == slot:
                    clip = candidate.clip if candidate.has_clip else None
                    previous = getattr(self, "_clip_identity", None)
                    identity = (ti, si, clip)
                    if previous != identity:
                        self._clip_identity = identity
                        self._clip_token = str(uuid.uuid4())
                    return track, slot, clip, ti, si, self._clip_token
        return None

    def clip_state(self):
        context = self.clip_context()
        if context is None:
            return None
        track, slot, clip, ti, si, token = context
        result = dict(token=token, track_index=ti, slot_index=si,
                      name=str(clip.name) if clip else "Empty slot", has_clip=clip is not None,
                      midi=bool(getattr(clip, "is_midi_clip", False)),
                      recording=bool(getattr(clip, "is_recording", False)),
                      can_create=bool(getattr(track, "has_midi_input", False)) and clip is None)
        if clip:
            for key in ("launch_mode", "launch_quantization", "legato", "looping", "velocity_amount"):
                if hasattr(clip, key):
                    result[key] = getattr(clip, key)
            result["can_transpose"] = result["midi"] and hasattr(clip, "get_notes_extended") and hasattr(clip, "apply_note_modifications")
        return result

    def execute_clip(self, command):
        context = self.clip_context()
        if context is None or command.get("clip_token") != context[-1]:
            raise ValueError("Selected clip changed; try again")
        track, slot, clip, ti, si, token = context
        action = command["action"]
        if action == "clip-new":
            if clip is not None or not getattr(track, "has_midi_input", False):
                raise ValueError("Select an empty MIDI slot")
            beats = self.song.signature_numerator * 4.0 / self.song.signature_denominator
            slot.create_clip(4 * beats)
            slot.clip.name = "New idea - 4 bars"
            self.song.view.detail_clip = slot.clip
            return
        if clip is None:
            raise ValueError("Select a Session clip")
        if getattr(clip, "is_recording", False):
            raise ValueError("Finish recording before editing the clip")
        if action == "clip-launch":
            clip.launch_mode = (int(clip.launch_mode) + 1) % 4
        elif action == "clip-quantization":
            values = (0, 5, 8, 10, 12, 1)
            current = int(clip.launch_quantization)
            clip.launch_quantization = values[(values.index(current) + 1) % len(values)] if current in values else 0
        elif action == "clip-legato":
            clip.legato = not clip.legato
        elif action == "clip-loop":
            clip.looping = not clip.looping
        elif action == "clip-velocity":
            clip.velocity_amount = (round(float(clip.velocity_amount) * 4) + 1) % 5 / 4.0
        elif action == "clip-duplicate":
            self.song.begin_undo_step()
            try:
                track.duplicate_clip_slot(si)
            finally:
                self.song.end_undo_step()
        elif action == "clip-double":
            if not clip.is_midi_clip:
                raise ValueError("Select a MIDI clip to duplicate its notes")
            clip.duplicate_loop()
        elif action in ("clip-up", "clip-down"):
            if not clip.is_midi_clip:
                raise ValueError("Select a MIDI clip")
            notes = clip.get_notes_extended(0, 128, 0, max(clip.end_marker, clip.loop_end))
            delta = 1 if action == "clip-up" else -1
            if not notes:
                raise ValueError("The clip has no notes")
            if any(not 0 <= note.pitch + delta <= 127 for note in notes):
                raise ValueError("Transposition would exceed the MIDI note range")
            for note in notes:
                note.pitch += delta
            clip.apply_note_modifications(notes)
        else:
            raise ValueError("Unknown clip command")

    def state(self):
        track = self.song.view.selected_track
        result = {"song_presets": bool(self.song_banks()),
                  "song_bank_values": [{"track": str(track.name), "value": int(selector.value)} for track, device, selector in self.song_banks()], "protocol": 1, "pid": os.getpid(), "session_id": self.session,
                  "time": self.clock(), "track_index": self.selected_index(),
                  "track_name": str(track.name), "can_arm": bool(track.can_be_armed),
                  "armed": bool(track.arm) if track.can_be_armed else False,
                  "tracks": [{"index": index, "name": str(item.name),
                              "can_arm": bool(item.can_be_armed)}
                             for index, item in enumerate(self.song.tracks)],
                  "arm_selection_source": self.arm_selection_source(),
                  "arm_selection_indices": [next((i for i, candidate in enumerate(self.song.tracks)
                                                  if candidate == selected), -1)
                                            for selected in self.selected_arm_targets()],
                  "last_id": self.last_id, "error": self.error}
        result.update({key: bool(getattr(self.song, prop))
                       for key, prop in TOGGLES.items()})
        result["quantization"] = int(self.song.midi_recording_quantization)
        result.update(performance=1, tempo_drag=1, playing=bool(self.song.is_playing),
                      tempo=float(self.song.tempo), loop_start=float(self.song.loop_start),
                      loop_length=float(self.song.loop_length),
                      beats_per_bar=self.song.signature_numerator * 4.0 / self.song.signature_denominator)
        intervals = list(getattr(self.song, "scale_intervals", ()))
        result.update(scale_supported=bool(intervals),
                      scale_mode=bool(getattr(self.song, "scale_mode", False)),
                      root_note=int(getattr(self.song, "root_note", 0)),
                      scale_name=str(getattr(self.song, "scale_name", "")),
                      scale_intervals=intervals)
        result["piano_mode_labels"] = self.piano_mode_labels()
        result["piano_modes"] = {channel: int(parameter.value)
                                 for channel, parameter in self.piano_modes().items()}
        result["clip_tools"] = 1
        result["selected_clip"] = self.clip_state() or {}
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
        if isinstance(action, str) and action.startswith("song-"):
            self.select_song_preset(action)
        elif isinstance(action, str) and action.startswith("clip-"):
            self.execute_clip(command)
        elif action == "piano-mode-set":
            mode = command.get("mode")
            channel = str(command.get("channel", ""))
            if type(mode) is not int or not 0 <= mode < len(self.piano_mode_labels().get(channel, ())):
                raise ValueError("Invalid piano mode")
            parameter = self.piano_modes().get(channel)
            if parameter is None:
                raise ValueError("No unique mode rack for this piano")
            parameter.value = mode
        elif action in TOGGLES:
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
        elif action == "tempo-set":
            tempo = float(command.get("tempo", float("nan")))
            if not math.isfinite(tempo):
                raise ValueError("Invalid tempo target")
            self.song.tempo = max(20.0, min(999.0, round(tempo, 2)))
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
        elif action in ("arm-on", "arm-off", "arm-exclusive", "arm-all-toggle"):
            track = self.song.view.selected_track
            if command.get("track_index") != self.selected_index():
                raise ValueError("Selected track changed; swipe again")
            selected_targets = self.selected_arm_targets()
            if action == "arm-all-toggle":
                armable = [item for item in self.song.tracks if item.can_be_armed]
                desired = not any(item.arm for item in armable)
                for item in armable:
                    item.arm = desired
                return
            if action == "arm-exclusive":
                requested_indices = command.get("track_indices")
                if isinstance(requested_indices, list):
                    selected_targets = []
                    for index in requested_indices:
                        if isinstance(index, bool) or not isinstance(index, int):
                            raise ValueError("Invalid selected track list")
                        if 0 <= index < len(self.song.tracks):
                            candidate = self.song.tracks[index]
                            if candidate.can_be_armed and candidate not in selected_targets:
                                selected_targets.append(candidate)
                if not selected_targets:
                    raise ValueError("No selected armable tracks")
                for item in self.song.tracks:
                    if item.can_be_armed:
                        item.arm = item in selected_targets
                return
            desired = action == "arm-on"
            # Touch Bar swipes are additive, like modifier-clicking Arm.
            # Do not implement Live's exclusive-arm UI preference here.
            requested_indices = command.get("track_indices")
            if isinstance(requested_indices, list):
                selected_targets = []
                for index in requested_indices:
                    if isinstance(index, bool) or not isinstance(index, int):
                        raise ValueError("Invalid selected track list")
                    if 0 <= index < len(self.song.tracks):
                        candidate = self.song.tracks[index]
                        if candidate.can_be_armed and candidate not in selected_targets:
                            selected_targets.append(candidate)
                if not selected_targets:
                    raise ValueError("No selected armable tracks")
            elif not selected_targets:
                raise ValueError("Select an audio or MIDI track")
            for item in selected_targets:
                item.arm = desired  # Explicit state: repeated swipes never toggle.
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
