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
    def test_arm_is_explicit_and_selected_only(self):
        for _ in range(2): self.server.execute(self.command("arm-on"))
        self.assertTrue(self.track.arm)
        self.assertFalse(self.other.arm)
        for _ in range(2): self.server.execute(self.command("arm-off"))
        self.assertFalse(self.track.arm)
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
