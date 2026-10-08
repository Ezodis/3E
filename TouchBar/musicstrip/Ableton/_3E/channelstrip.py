from __future__ import absolute_import, print_function, unicode_literals
import sys
if sys.version_info[0] == 3:
    from future.builtins import round
    from past.builtins import unicode
    from builtins import range
import re
import Live
from ableton.v2.base import liveobj_valid, listens, listens_group, task
from ableton.v2.control_surface.components import ChannelStripComponent as ChannelStripComponentBase
from ableton.v2.control_surface.control import ButtonControl
from .sysex import MTSysex

def _try_to_round_number(parameter_string):
    value_as_number = None
    try:
        value_as_number = int(parameter_string)
    except ValueError:
        pass
    if value_as_number is None:
        try:
            value_as_number = round(float(parameter_string), 1)
        except ValueError:
            pass
    return value_as_number
    
large_pattern = re.compile(u'\\d|\\xb0|/|\\%|\\.|\\:|\\-|\\+|inf')
    
def get_rounded_value_string(parameter):
    parameter_string = unicode(parameter)
    large_string = u''.join(large_pattern.findall(parameter_string))
    if large_string in (u'inf', u'-inf'):
        return large_string + ' dB'
    large_number = _try_to_round_number(large_string)
    if large_number is None:
        return parameter_string
    if large_string.startswith(u'+'):
        return u'+' + unicode(large_number) + ' dB'
    return unicode(large_number) + ' dB'

class ChannelStripComponent(ChannelStripComponentBase):

    volume_touch = ButtonControl()
    pan_touch = ButtonControl()
    send_touch_1 = ButtonControl()
    send_touch_2 = ButtonControl()
    send_touch_3 = ButtonControl()
    send_touch_4 = ButtonControl()

    def __init__(self, *a, **k):
        super(ChannelStripComponent, self).__init__(*a, **k)
        self._reset_volume_display_task = task.Task()
        self.volume_touch_state = False
        self._reset_pan_display_task = task.Task()
        self.pan_touch_state = False
        self._reset_send_display_tasks = [task.Task(), task.Task(), task.Task(), task.Task()]
        self.send_touch_states = [False, False, False, False]
        
    @listens_group(u'name')
    def __on_return_track_name_changed(self, return_track):
        for num, track in enumerate(self.song.return_tracks):
            if track == return_track:
                self.__send_send_name(num)
        
    def set_track(self, track):
        super(ChannelStripComponent, self).set_track(track)
        self._reset_volume_display_task.kill()
        self._reset_pan_display_task.kill()
        for display_task in self._reset_send_display_tasks:
            display_task.kill()
        self.__send_track_name()
        self.__send_pan_name()
        self.__on_track_color_changed.subject = track if liveobj_valid(track) else None
        self.__send_track_color()
        self.__on_volume_value_changed.subject = track if liveobj_valid(track) else None
        self.__on_pan_value_changed.subject = track if liveobj_valid(track) else None
        num_sends = len(self._track.mixer_device.sends)
        for i in range(num_sends):
            self.__send_send_name(i)
        for i in range(4 - num_sends):
            num = i + num_sends
            sysex = MTSysex()
            sysex.sendSendMessage(num, u'Send' + str(num + 1))
            sysex.send()
        
    def update(self):
        super(ChannelStripComponent, self).update()
        mixer = self._track.mixer_device if liveobj_valid(self._track) else None
        self.__on_send_a_value_changed.subject = mixer.sends[0] if mixer and len(mixer.sends) else None
        self.__on_send_b_value_changed.subject = mixer.sends[1] if mixer and len(mixer.sends) > 1 else None
        self.__on_send_c_value_changed.subject = mixer.sends[2] if mixer and len(mixer.sends) > 2 else None
        self.__on_send_d_value_changed.subject = mixer.sends[3] if mixer and len(mixer.sends) > 3 else None
        if mixer:
            self.__on_return_track_name_changed.replace_subjects(self.song.return_tracks[:len(mixer.sends)])


    def _on_track_name_changed(self):
        self.__send_track_name()
    
    def __send_track_name(self):
        track_name = u'-'
        if liveobj_valid(self._track):
            track_name = self._track.name
        sysex = MTSysex()
        sysex.trackNameMessage(track_name)
        sysex.send()
        
    @listens(u'color')
    def __on_track_color_changed(self):
        self.__send_track_color()

    def __send_track_color(self):
        sysex = MTSysex()
        sysex.colorMessage(self._track.color)
        sysex.send()
        
    def __send_track_volume(self):
        if liveobj_valid(self._track):
            volume = get_rounded_value_string(self._track.mixer_device.volume)
            sysex = MTSysex()
            sysex.trackNameMessage(volume)
            sysex.send()
            
    def __send_pan_name(self):
        sysex = MTSysex()
        sysex.panNameMessage(u'Pan')
        sysex.send()
        
    def __send_pan_value(self):
        if liveobj_valid(self._track):
            pan = unicode(self._track.mixer_device.panning)
            sysex = MTSysex()
            sysex.panNameMessage(pan)
            sysex.send()
            
    def __send_send_name(self, num):
        name = self.song.return_tracks[num].name
        sysex = MTSysex()
        sysex.sendSendMessage(num, name)
        sysex.send()
        
    def __send_send_value(self, num):
        if liveobj_valid(self._track) and len(self._track.mixer_device.sends) > num:
            send = get_rounded_value_string(self._track.mixer_device.sends[num])
            sysex = MTSysex()
            sysex.sendSendMessage(num, send)
            sysex.send()

    @volume_touch.pressed
    def volume_touch(self, button):
        self.volume_touch_button_toggle(button.is_pressed)
        
    @volume_touch.released
    def volume_touch(self, button):
        self.volume_touch_button_toggle(button.is_pressed)
        
    @volume_touch.double_clicked
    def volume_touch(self, _):
        self.reset_volume_to_default()
        
    @pan_touch.pressed
    def pan_touch(self, button):
        self.pan_touch_button_toggle(button.is_pressed)
        
    @pan_touch.released
    def pan_touch(self, button):
        self.pan_touch_button_toggle(button.is_pressed)
        
    @pan_touch.double_clicked
    def pan_touch(self, _):
        self.reset_pan_to_default()
        
    @send_touch_1.pressed
    def send_touch_1(self, button):
        self.send_touch_button_toggle(0, button.is_pressed)
        
    @send_touch_1.released
    def send_touch_1(self, button):
        self.send_touch_button_toggle(0, button.is_pressed)
        
    @send_touch_1.double_clicked
    def send_touch_1(self, _):
        self.reset_send_to_default(0)
        
    @send_touch_2.pressed
    def send_touch_2(self, button):
        self.send_touch_button_toggle(1, button.is_pressed)
        
    @send_touch_2.released
    def send_touch_2(self, button):
        self.send_touch_button_toggle(1, button.is_pressed)
        
    @send_touch_2.double_clicked
    def send_touch_2(self, _):
        self.reset_send_to_default(1)
        
    @send_touch_3.pressed
    def send_touch_3(self, button):
        self.send_touch_button_toggle(2, button.is_pressed)
        
    @send_touch_3.released
    def send_touch_3(self, button):
        self.send_touch_button_toggle(2, button.is_pressed)
        
    @send_touch_3.double_clicked
    def send_touch_3(self, _):
        self.reset_send_to_default(2)
        
    @send_touch_4.pressed
    def send_touch_4(self, button):
        self.send_touch_button_toggle(3, button.is_pressed)
        
    @send_touch_4.released
    def send_touch_4(self, button):
        self.send_touch_button_toggle(3, button.is_pressed)
        
    @send_touch_4.double_clicked
    def send_touch_4(self, _):
        self.reset_send_to_default(3)

    @listens(u'mixer_device.volume.value')
    def __on_volume_value_changed(self):
         if self.volume_touch_state:
            self.__send_track_volume()
                
    @listens(u'mixer_device.panning.value')
    def __on_pan_value_changed(self):
         if self.pan_touch_state:
            self.__send_pan_value()
        
    @listens(u'value')
    def __on_send_a_value_changed(self):
        if self.send_touch_states[0]:
            self.__send_send_value(0)

    @listens(u'value')
    def __on_send_b_value_changed(self):
        if self.send_touch_states[1]:
            self.__send_send_value(1)
        
    @listens(u'value')
    def __on_send_c_value_changed(self):
        if self.send_touch_states[2]:
            self.__send_send_value(2)

    @listens(u'value')
    def __on_send_d_value_changed(self):
        if self.send_touch_states[3]:
            self.__send_send_value(3)
        

    def volume_touch_button_toggle(self, is_toggled):
        self.volume_touch_state = is_toggled
        if not is_toggled:
            self._reset_volume_display_task.kill()
            self._reset_volume_display_task = self._tasks.add(task.sequence(task.wait(1), task.run(self.reset_volume_display)))
        else:
            self.show_volume_value()

    def show_volume_value(self):
        self.__send_track_volume()
                    
    def reset_volume_display(self):
        self.__send_track_name()

    def reset_volume_to_default(self):
        if self._track != None:
            volume = self._track.mixer_device.volume
            if volume.is_enabled:
                volume.value = volume.default_value
                self.__send_track_volume()
                

    def pan_touch_button_toggle(self, is_toggled):
        self.pan_touch_state = is_toggled
        if not is_toggled:
            self._reset_pan_display_task.kill()
            self._reset_pan_display_task = self._tasks.add(task.sequence(task.wait(1), task.run(self.reset_pan_display)))
        else:
            self.show_pan_value()

    def show_pan_value(self):
        self.__send_pan_value()
                    
    def reset_pan_display(self):
        self.__send_pan_name()

    def reset_pan_to_default(self):
        if self._track != None:
            pan = self._track.mixer_device.panning
            if pan.is_enabled:
                pan.value = pan.default_value
                self.__send_pan_value()
                

    def send_touch_button_toggle(self, num, is_toggled):
        self.send_touch_states[num] = is_toggled
        if not is_toggled:
            self._reset_send_display_tasks[num].kill()
            self._reset_send_display_tasks[num] = self._tasks.add(task.sequence(task.wait(1), task.run(self.reset_send_display, num)))
        else:
            self.show_send_value(num)
            
    def show_send_value(self, num):
        self.__send_send_value(num)

    def reset_send_display(self, num):
        self.__send_send_name(num)

    def reset_send_to_default(self, num):
        if liveobj_valid(self._track) and len(self._track.mixer_device.sends) > num:
            send = self._track.mixer_device.sends[num]
            if send.is_enabled:
                send.value = send.default_value
                self.__send_send_value(num)

