# SPDX-License-Identifier: MIT
import importlib.util
from pathlib import Path
from types import SimpleNamespace as NS
import unittest

spec = importlib.util.spec_from_file_location('phone_mapping', Path(__file__).parent / '_3E_Phone_Bar' / 'mapping.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def parameter(name='', low=0, high=1):
    return NS(name=name, original_name=name, min=low, max=high, value=.5, is_enabled=True, is_quantized=False)

class MappingTest(unittest.TestCase):
    def setUp(self):
        self.fired=[]; self.stopped=[]; self.jogged=[]; self.messages=[]
        tracks=[]
        for i in range(8):
            clip=NS(is_recording=False, is_midi_clip=True, warping=False, move_playing_pos=self.jogged.append)
            slot=NS(has_clip=True, clip=clip, fire=lambda i=i:self.fired.append(i))
            mixer=NS(volume=parameter(),panning=parameter(low=-1),sends=[parameter()],crossfade_assign=1)
            tracks.append(NS(mixer_device=mixer,mute=False,solo=False,clip_slots=[slot],playing_slot_index=0,devices=[],stop_all_clips=lambda i=i:self.stopped.append(i)))
        scene=object()
        self.song=NS(tracks=tracks,scenes=[scene],view=NS(selected_scene=scene,selected_track=None,highlighted_clip_slot=None),master_track=NS(mixer_device=NS(crossfader=parameter(low=-1))))
        self.mapping=module.Mapping(self.song,self.messages.append)

    def test_mixer(self):
        for i,t in enumerate(self.song.tracks):
            for cc,p in [(16+i,t.mixer_device.volume),(24+i,t.mixer_device.panning),(32+i,t.mixer_device.sends[0])]:
                self.mapping.receive(False,cc,127);self.assertEqual(p.value,p.max)
                self.mapping.receive(False,cc,0);self.assertEqual(p.value,p.min)
            for n,attr in [(48+i,'mute'),(56+i,'solo')]:
                self.mapping.receive(True,n,127);self.assertTrue(getattr(t,attr))
                self.mapping.receive(True,n,0);self.assertTrue(getattr(t,attr))
                self.mapping.receive(True,n,127);self.assertFalse(getattr(t,attr))

    def test_decks(self):
        for i in range(2):
            self.mapping.receive(True,36+i,127);self.mapping.receive(True,42+i,127)
            self.mapping.receive(True,38+i,127);self.assertIs(self.song.view.selected_track,self.song.tracks[i])
            self.mapping.receive(False,40+i,65);self.mapping.receive(False,40+i,63)
        self.assertEqual(self.fired,[0,1]);self.assertEqual(self.stopped,[0,1]);self.assertEqual(self.jogged,[.0625,-.0625,.0625,-.0625])
        self.mapping.receive(False,1,127);self.assertEqual(self.song.master_track.mixer_device.crossfader.value,1)
        self.assertEqual([t.mixer_device.crossfade_assign for t in self.song.tracks[:2]],[0,2])

    def test_empty_and_recording_clips_are_not_triggered(self):
        slot=self.song.tracks[0].clip_slots[0];slot.has_clip=False
        self.mapping.receive(True,36,127);self.assertFalse(self.fired)
        slot.has_clip=True;slot.clip.is_recording=True
        self.mapping.receive(False,40,65);self.assertFalse(self.jogged)

    def test_missing_tracks_sends_and_effects(self):
        self.song.tracks=self.song.tracks[:1];self.song.tracks[0].mixer_device.sends=[]
        for cc in module.CCS:self.mapping.receive(False,cc,100)
        for note in module.NOTES:self.mapping.receive(True,note,127)
        self.assertTrue(self.messages)

    def test_nested_deck_effects(self):
        eq=[parameter(name) for name in ['GainLo','GainMid','GainHi']];freq=parameter('Frequency',20,20000)
        self.song.tracks[0].devices=[NS(class_name='AudioEffectGroupDevice',parameters=[],can_have_chains=True,chains=[NS(devices=[NS(class_name='FilterEQ3',parameters=eq),NS(class_name='AutoFilter',parameters=[freq])])])]
        for cc,p in [(48,freq),(50,eq[0]),(52,eq[1]),(54,eq[2])]:
            self.mapping.receive(False,cc,127);self.assertEqual(p.value,p.max)

    def test_controls_only_reserve_channel_16(self):
        self.assertEqual(module.CONTROL_CHANNEL,15)
        self.assertEqual(len(module.NOTES),len(set(module.NOTES)))
        self.assertEqual(len(module.CCS),len(set(module.CCS)))

if __name__=='__main__':unittest.main()
