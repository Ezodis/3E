import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
import uuid

spec = importlib.util.spec_from_file_location("strip3_record", Path(__file__).parents[1] / "Ableton/_3E/strip3_record.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class RecordTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.track = SimpleNamespace(name="MIDI", can_be_armed=True, arm=False)
        self.other = SimpleNamespace(name="Audio", can_be_armed=True, arm=False)
        self.song = SimpleNamespace(view=SimpleNamespace(selected_track=self.track), tracks=[self.track, self.other], exclusive_arm=True, midi_recording_quantization=0,
            is_playing=False, tempo=120.0, loop_start=0.0, loop_length=16.0,
            signature_numerator=4, signature_denominator=4, current_song_time=19.0)
        self.song.scale_mode, self.song.root_note, self.song.scale_name = True, 0, "Major"
        self.song.scale_intervals = (0,2,4,5,7,9,11)
        self.calls = []
        self.song.continue_playing = lambda: (self.calls.append("continue"), setattr(self.song, "is_playing", True))
        self.song.stop_playing = lambda: (self.calls.append("stop"), setattr(self.song, "is_playing", False))
        self.song.tap_tempo = lambda: self.calls.append("tap")
        self.song.trigger_session_record = lambda: self.calls.append("session-record")
        self.song.stop_all_clips = lambda: self.calls.append("stop-clips-quantized")
        self.song.re_enable_automation = lambda: self.calls.append("re-enable")
        for prop in module.TOGGLES.values(): setattr(self.song, prop, False)
        self.server = module.RecordServer(self.song, self.directory.name, clock=lambda:100)
    def tearDown(self):
        self.server.close()
        self.directory.cleanup()
    def command(self, action, **changes):
        command = dict(action=action, session=self.server.session, time=100, track_index=0)
        command.update(changes)
        return command
    def test_song_loop_envelopes_are_native_and_not_overwritten(self):
        selector = SimpleNamespace(name="Chain Selector", value=0)
        steps = []
        envelope = SimpleNamespace(insert_step=lambda *args: steps.append(args))
        clip = SimpleNamespace(name="RUFF - Base", is_recording=False, loop_start=0, loop_end=16,
                               automation_envelope=lambda parameter: None,
                               create_automation_envelope=lambda parameter: envelope)
        self.track.name = "P2 MIDI LOOPS - Chords"
        self.track.devices = [SimpleNamespace(name="SONG: 0 DIABLA | 1 RUFF | 2 NOTA", parameters=[selector], chains=[None]*3)]
        self.track.clip_slots = [SimpleNamespace(has_clip=True, clip=clip)]
        self.server.execute(self.command("song-bind-loops"))
        self.assertEqual(steps, [(0, 16, 1)])
        clip.automation_envelope = lambda parameter: envelope
        self.server.execute(self.command("song-bind-loops"))
        self.assertEqual(len(steps), 1)

    def test_song_bank_switch_and_active_chord_mode(self):
        banks = []
        for track in (self.track, self.other):
            selector = SimpleNamespace(name="Chain Selector", value=0)
            modes = [SimpleNamespace(name="Chain Selector", value=i) for i in range(3)]
            chains = [SimpleNamespace(devices=[SimpleNamespace(name="MODE: 0 Plain | 1 Arp | 2 Bounce", parameters=[mode])]) for mode in modes]
            bank = SimpleNamespace(name="SONG: 0 DIABLA | 1 RUFF | 2 NOTA", parameters=[selector], chains=chains)
            track.devices = [bank]
            banks.append((selector, modes))
        self.track.name, self.other.name = "P1 MELODY - Ch 1", "P2 CHORDS - Ch 2"
        self.song.begin_undo_step = lambda: None
        self.song.end_undo_step = lambda: None
        self.song.scenes = [SimpleNamespace(name="RUFF - Base")]
        self.server.execute(self.command("song-ruff"))
        self.assertEqual(self.song.tempo, 108)
        self.assertEqual((self.song.root_note, self.song.scale_name), (1, "Major"))
        self.assertEqual(self.server.state()["piano_modes"], {"1": 1, "2": 1})
        self.server.execute(self.command("piano-mode-set", channel="2", mode=2))
        self.assertEqual(banks[1][1][1].value, 2)
        self.assertEqual(banks[1][1][0].value, 0)
        self.song.record_mode = True
        with self.assertRaises(ValueError): self.server.execute(self.command("song-nota"))
        self.assertEqual(self.song.tempo, 108)

    def test_piano_mode_changes_only_matching_rack(self):
        selector = SimpleNamespace(name="Chain Selector", original_name="Chain Selector", value=2)
        self.track.name = "P2 CHORDS - Ch 2"
        self.track.devices = [SimpleNamespace(name="MODE: 0 Plain | 1 Arp | 2 Bounce", parameters=[selector])]
        self.assertEqual(self.server.state()["piano_modes"], {"2": 2})
        for mode in (0, 1, 2):
            self.server.execute(self.command("piano-mode-set", channel="2", mode=mode))
            self.assertEqual(selector.value, mode)
        self.assertEqual(self.song.scale_name, "Major")
        for payload in ({"channel": "1", "mode": 1}, {"channel": "2", "mode": 3}, {"channel": "2", "mode": True}):
            with self.assertRaises(ValueError):
                self.server.execute(self.command("piano-mode-set", **payload))
        self.other.name = self.track.name
        self.other.devices = self.track.devices
        self.assertEqual(self.server.state()["piano_modes"], {})
        with self.assertRaises(ValueError):
            self.server.execute(self.command("piano-mode-set", channel="2", mode=0))

    def prepare_clip(self):
        clip = SimpleNamespace(name="Base", is_midi_clip=True, is_recording=False,
            launch_mode=0, launch_quantization=0, legato=False, looping=True,
            velocity_amount=0.0, end_marker=16, loop_end=16)
        slot = SimpleNamespace(has_clip=True, clip=clip)
        self.track.clip_slots = [slot]
        self.track.has_midi_input = True
        self.song.view.highlighted_clip_slot = slot
        return clip, slot

    def test_clip_settings_are_selected_and_acknowledged(self):
        clip, slot = self.prepare_clip()
        token = self.server.state()["selected_clip"]["token"]
        for action in ("clip-launch", "clip-quantization", "clip-legato", "clip-loop", "clip-velocity"):
            self.server.execute(self.command(action, clip_token=token))
        self.assertEqual((clip.launch_mode, clip.launch_quantization, clip.legato, clip.looping, clip.velocity_amount), (1, 5, True, False, .25))
        self.assertEqual(self.song.loop_length, 16)  # Never edit Arrangement loop.
        self.song.view.highlighted_clip_slot = None
        with self.assertRaises(ValueError):
            self.server.execute(self.command("clip-loop", clip_token=token))
        self.assertEqual(self.server.state()["selected_clip"], {})

    def test_replaced_or_recording_clip_rejects_edits(self):
        clip, slot = self.prepare_clip()
        token = self.server.state()["selected_clip"]["token"]
        clip.is_recording = True
        with self.assertRaises(ValueError):
            self.server.execute(self.command("clip-duplicate", clip_token=token))
        slot.clip = SimpleNamespace(name="Replacement")
        with self.assertRaises(ValueError):
            self.server.execute(self.command("clip-launch", clip_token=token))

    def test_transpose_checks_entire_range_before_writing(self):
        clip, slot = self.prepare_clip()
        notes = [SimpleNamespace(pitch=60), SimpleNamespace(pitch=127)]
        clip.get_notes_extended = lambda *args: notes
        clip.apply_note_modifications = lambda ns: self.calls.append([n.pitch for n in ns])
        token = self.server.state()["selected_clip"]["token"]
        with self.assertRaises(ValueError):
            self.server.execute(self.command("clip-up", clip_token=token))
        self.assertEqual([n.pitch for n in notes], [60, 127])
        self.server.execute(self.command("clip-down", clip_token=token))
        self.assertEqual(self.calls, [[59, 126]])

    def test_new_clip_never_overwrites_and_uses_time_signature(self):
        clip, slot = self.prepare_clip()
        token = self.server.state()["selected_clip"]["token"]
        with self.assertRaises(ValueError):
            self.server.execute(self.command("clip-new", clip_token=token))
        slot.has_clip = False
        slot.create_clip = lambda beats: self.calls.append(beats)
        self.song.signature_numerator = 3
        token = self.server.state()["selected_clip"]["token"]
        self.server.execute(self.command("clip-new", clip_token=token))
        self.assertEqual(self.calls, [12])

    def test_arm_is_explicit_and_selected_only(self):
        for _ in range(2): self.server.execute(self.command("arm-on"))
        self.assertTrue(self.track.arm)
        self.assertFalse(self.other.arm)
        for _ in range(2): self.server.execute(self.command("arm-off"))
        self.assertFalse(self.track.arm)
    def test_arm_swipes_apply_to_every_selected_armable_track(self):
        self.song.view.selected_tracks = [self.track, self.other]
        self.server.execute(self.command("arm-on"))
        self.assertTrue(self.track.arm)
        self.assertTrue(self.other.arm)
        self.server.execute(self.command("arm-off"))
        self.assertFalse(self.track.arm)
        self.assertFalse(self.other.arm)
    def test_arm_swipes_find_track_level_multi_selection(self):
        self.song.view.selected_tracks = None
        self.track.is_selected = True
        self.other.is_selected = True
        self.server.execute(self.command("arm-on"))
        self.assertTrue(self.track.arm)
        self.assertTrue(self.other.arm)
        self.server.execute(self.command("arm-off"))
        self.assertFalse(self.track.arm)
        self.assertFalse(self.other.arm)
    def test_arm_swipes_accept_accessibility_selected_track_indices(self):
        self.server.execute(self.command("arm-on", track_indices=[0, 1]))
        self.assertTrue(self.track.arm)
        self.assertTrue(self.other.arm)
        self.server.execute(self.command("arm-off", track_indices=[0, 1]))
        self.assertFalse(self.track.arm)
        self.assertFalse(self.other.arm)
    def test_control_surface_exclusive_arms_every_selected_track_only(self):
        third = SimpleNamespace(name="Unselected", can_be_armed=True, arm=True)
        self.song.tracks.append(third)
        self.other.arm = True
        self.server.execute(self.command("arm-exclusive", track_indices=[0, 1]))
        self.assertTrue(self.track.arm)
        self.assertTrue(self.other.arm)
        self.assertFalse(third.arm)
    def test_stale_or_changed_track_cannot_act(self):
        for changes in ({"session":"old"}, {"time":90}, {"time":110}):
            with self.assertRaises(ValueError): self.server.execute(self.command("record", **changes))
        self.song.view.selected_track=self.other
        with self.assertRaises(ValueError): self.server.execute(self.command("arm-on"))
        self.assertFalse(self.other.arm)
        self.assertFalse(self.song.record_mode)
    def test_arm_swipes_accumulate_even_with_exclusive_arm_enabled(self):
        self.server.execute(self.command("arm-on"))
        self.song.view.selected_track = self.other
        self.server.execute(self.command("arm-on", track_index=1))
        self.server.execute(self.command("arm-on", track_index=1))
        self.assertTrue(self.track.arm)
        self.assertTrue(self.other.arm)
        self.assertTrue(self.song.exclusive_arm)  # Never change Live preferences.
        self.server.execute(self.command("arm-off", track_index=1))
        self.assertTrue(self.track.arm)
        self.assertFalse(self.other.arm)
    def test_return_or_master_track_rejected(self):
        self.track.can_be_armed=False
        with self.assertRaises(ValueError): self.server.execute(self.command("arm-on"))
    def test_transport_and_tap_use_live_functions(self):
        for action in ("play", "play", "stop", "tap-tempo", "session-capture", "stop-clips", "re-enable-automation"):
            self.server.execute(self.command(action))
        self.assertEqual(self.calls, ["continue", "stop", "stop", "tap", "session-record", "stop-clips-quantized", "re-enable"])
    def test_tempo_steps_and_limits(self):
        for action, expected in (("tempo-up",121), ("tempo-down",120), ("tempo-up-fine",120.1), ("tempo-down-fine",120)):
            self.server.execute(self.command(action)); self.assertAlmostEqual(self.song.tempo, expected)
        self.song.tempo = 20; self.server.execute(self.command("tempo-down")); self.assertEqual(self.song.tempo, 20)
        self.song.tempo = 999; self.server.execute(self.command("tempo-up")); self.assertEqual(self.song.tempo, 999)
    def test_loops_use_current_bar_and_time_signature(self):
        for bars in (1,2,4,8):
            self.server.execute(self.command("loop-%d" % bars))
            self.assertEqual(self.song.loop_start, 16)
            self.assertEqual(self.song.loop_length, bars * 4)
            self.assertTrue(self.song.loop)
        self.song.signature_numerator, self.song.signature_denominator = 6, 8
        self.server.execute(self.command("loop-2"))
        self.assertEqual((self.song.loop_start, self.song.loop_length), (18,6))
    def test_proportional_tempo_targets_and_validation(self):
        self.assertEqual(self.server.state()["tempo_drag"], 1)
        for target, expected in ((128.5,128.5), (110.5,110.5), (122.5,122.5), (-1,20), (1001,999)):
            self.server.execute(self.command("tempo-set", tempo=target))
            self.assertEqual(self.song.tempo, expected)
        for target in (float("nan"), float("inf"), "invalid"):
            with self.assertRaises(ValueError): self.server.execute(self.command("tempo-set", tempo=target))
    def test_loop_movement_and_resize_do_not_seek_or_change_record(self):
        self.server.execute(self.command("loop-next")); self.assertEqual(self.song.loop_start, 16)
        self.server.execute(self.command("loop-prev")); self.assertEqual(self.song.loop_start, 0)
        self.server.execute(self.command("loop-prev")); self.assertEqual(self.song.loop_start, 0)
        self.server.execute(self.command("loop-half")); self.assertEqual(self.song.loop_length, 8)
        self.server.execute(self.command("loop-double")); self.assertEqual(self.song.loop_length, 16)
        self.assertEqual(self.song.current_song_time, 19)
        self.assertFalse(self.song.record_mode)
    def test_performance_state_reports_live_values(self):
        state = self.server.state()
        self.assertEqual((state["performance"], state["tempo"], state["loop_length"], state["beats_per_bar"]), (1,120,16,4))
        self.assertFalse(state["playing"])
    def test_scale_feedback_tracks_live_root_and_intervals(self):
        state = self.server.state()
        self.assertEqual((state["root_note"], state["scale_name"], state["scale_intervals"]), (0,"Major",[0,2,4,5,7,9,11]))
        self.song.root_note, self.song.scale_name = 6, "Minor"
        self.song.scale_intervals = (0,2,3,5,7,8,10)
        state = self.server.state()
        self.assertEqual((state["root_note"], state["scale_name"], state["scale_intervals"]), (6,"Minor",[0,2,3,5,7,8,10]))
        self.song.scale_mode = False
        self.assertFalse(self.server.state()["scale_mode"])
    def test_missing_scale_api_does_not_guess_a_scale(self):
        del self.song.scale_intervals
        self.assertFalse(self.server.state()["scale_supported"])
    def test_options_change_real_properties(self):
        for action, prop in module.TOGGLES.items():
            self.server.execute(self.command(action)); self.assertTrue(getattr(self.song, prop))
            self.server.execute(self.command(action)); self.assertFalse(getattr(self.song, prop))
        for expected in (2, 5, 0):
            self.server.execute(self.command("quantization"))
            self.assertEqual(self.song.midi_recording_quantization, expected)
    def test_acknowledged_toggle_consumed_once(self):
        token=str(uuid.uuid4())
        path=Path(self.server.commands) / (token+".json")
        path.write_text(json.dumps(self.command("record")))
        self.server.poll(); self.server.poll()
        self.assertTrue(self.song.record_mode)
        self.assertFalse(path.exists())
        response=json.loads((Path(self.server.responses)/(token+".json")).read_text())
        self.assertTrue(response["ok"])
        self.assertTrue(response["state"]["record"])
    def test_single_server(self):
        other=module.RecordServer(self.song, self.directory.name)
        self.assertFalse(other.active)
        other.close()
        self.assertTrue((Path(self.directory.name)/"state.json").exists())
    def test_session_identity_does_not_collide_with_session_record(self):
        state=self.server.state()
        self.assertEqual(state["session_id"], self.server.session)
        self.assertIs(state["session"], False)

if __name__ == "__main__": unittest.main()
