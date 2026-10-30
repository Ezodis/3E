# SPDX-License-Identifier: MIT
# Kept independent of Live's framework so routing can be tested without a DAW.
CONTROL_CHANNEL = 15
CCS = (1,) + tuple(range(16, 42)) + tuple(range(48, 56))
NOTES = (64, 65) + tuple(range(68, 76)) + (36, 37, 38, 39, 42, 43) + tuple(range(48, 64))


class Mapping:
    def __init__(self, song, show_message=lambda message: None):
        self.song = song
        self.show = show_message

    def track(self, index):
        tracks = self.song.tracks
        return tracks[index] if 0 <= index < len(tracks) else None

    def parameter(self, parameter, value):
        if parameter is not None and parameter.is_enabled:
            scaled = parameter.min + (parameter.max - parameter.min) * value / 127.0
            parameter.value = round(scaled) if parameter.is_quantized else scaled

    def slot(self, track):
        scenes = tuple(self.song.scenes)
        scene = self.song.view.selected_scene
        index = scenes.index(scene) if scene in scenes else 0
        return track.clip_slots[index] if index < len(track.clip_slots) else None

    def effect(self, track, class_name, names):
        def search(devices):
            for device in devices:
                if device.class_name == class_name:
                    for parameter in device.parameters:
                        if getattr(parameter, 'original_name', parameter.name) in names:
                            return parameter
                for chain in (device.chains if getattr(device, 'can_have_chains', False) else ()):
                    found = search(chain.devices)
                    if found is not None:
                        return found
            return None
        return search(track.devices)

    def receive(self, note, number, value):
        if note:
            if not value:
                return
            if 64 <= number <= 75:
                index = number - 64 if number < 66 else (number - 68) // 4
                track = self.track(index)
                if track is None:
                    return
                if number < 66:
                    at = track.playing_slot_index
                    slot = track.clip_slots[at] if at >= 0 and at < len(track.clip_slots) else self.slot(track)
                    if slot is not None and slot.has_clip:
                        slot.clip.looping = not slot.clip.looping
                elif number >= 68:
                    at = (number - 68) % 4
                    if at < len(track.clip_slots) and track.clip_slots[at].has_clip:
                        track.clip_slots[at].fire()
                return
            if 48 <= number <= 63:
                index = number - (48 if number < 56 else 56)
                track = self.track(index)
                if track is not None:
                    attribute = 'mute' if number < 56 else 'solo'
                    setattr(track, attribute, not getattr(track, attribute))
                return
            index = number % 2
            track = self.track(index)
            if track is None:
                return
            if number in (36, 37):
                if track.playing_slot_index >= 0:
                    track.stop_all_clips()
                    return
                slot = self.slot(track)
                if slot is not None and slot.has_clip:
                    slot.fire()
                else:
                    self.show('3E Phone Bar: place a clip in the selected scene on deck %s' % ('B' if index else 'A'))
            elif number in (42, 43):
                track.stop_all_clips()
            elif number in (38, 39):
                self.song.view.selected_track = track
                slot = self.slot(track)
                if slot is not None:
                    self.song.view.highlighted_clip_slot = slot
            return
        if number == 1:
            self.parameter(self.song.master_track.mixer_device.crossfader, value)
            # Assign A/B only when the deck crossfader is actually used.
            for index, assignment in ((0, 0), (1, 2)):
                track = self.track(index)
                if track is not None:
                    track.mixer_device.crossfade_assign = assignment
            return
        if 16 <= number <= 39:
            group = (number - 16) // 8
            track = self.track((number - 16) % 8)
            if track is not None:
                mixer = track.mixer_device
                parameter = mixer.volume if group == 0 else mixer.panning if group == 1 else mixer.sends[0] if mixer.sends else None
                self.parameter(parameter, value)
            return
        if number in (40, 41):
            track = self.track(number - 40)
            if track is not None and track.playing_slot_index >= 0:
                slot = track.clip_slots[track.playing_slot_index]
                if slot.has_clip and not slot.clip.is_recording and (slot.clip.is_midi_clip or slot.clip.warping):
                    slot.clip.move_playing_pos((value - 64) * .0625)
            return
        if 48 <= number <= 55:
            track = self.track(number % 2)
            if track is None:
                return
            if number < 50:
                parameter = self.effect(track, 'AutoFilter', ('Frequency', 'Filter Freq'))
            else:
                names = (('GainLo', 'Gain Low'), ('GainMid', 'Gain Mid'), ('GainHi', 'Gain High'))[(number - 50) // 2]
                parameter = self.effect(track, 'FilterEQ3', names)
            if parameter is None:
                self.show('3E Phone Bar: add %s to this deck to use its knob' % ('Auto Filter' if number < 50 else 'EQ Three'))
            self.parameter(parameter, value)
