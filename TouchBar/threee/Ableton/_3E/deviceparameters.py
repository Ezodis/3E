from __future__ import absolute_import, print_function, unicode_literals
import sys
if sys.version_info[0] == 3:
    from builtins import range
    from past.builtins import unicode
import Live
from itertools import chain, repeat
from ableton.v2.base import listens, listens_group, task
from ableton.v2.control_surface.components import DisplayingDeviceParameterComponent as DeviceParameterComponentBase
from ableton.v2.control_surface import is_parameter_quantized
from ableton.v2.control_surface.control import ButtonControl
from .sysex import MTSysex

def is_parameter_button(parameter):
    isButton = is_parameter_quantized(parameter, parameter and parameter.canonical_parent)
    if parameter.max!=1:
        isButton = False
    return isButton

class DeviceParameterComponent(DeviceParameterComponentBase):

    touch_button_1 = ButtonControl()
    touch_button_2 = ButtonControl()
    touch_button_3 = ButtonControl()
    touch_button_4 = ButtonControl()
    touch_button_5 = ButtonControl()
    touch_button_6 = ButtonControl()
    touch_button_7 = ButtonControl()
    touch_button_8 = ButtonControl()

    def __init__(self, *a, **k):
        super(DeviceParameterComponent, self).__init__(*a, **k)
        self.clear_display()
        self._reset_display_tasks = [task.Task(), task.Task(), task.Task(), task.Task(), task.Task(), task.Task(), task.Task(), task.Task()]
        
    def clear_display(self):
        self.button_touch_states = [False, False, False, False, False, False, False, False]
        self.display_strings = ['', '', '', '', '', '', '', '']
        self.display_kind = [False, False, False, False, False, False, False, False]
        self.display_enabled = [False, False, False, False, False, False, False, False]
        
    def _update_parameter_names(self):
        if self.is_enabled():
            for num, info in enumerate(self.parameter_provider.parameters):
                is_button = False
                is_enabled = False
                parameter = info.parameter
                if parameter:
                    is_enabled = True
                    is_button = is_parameter_button(parameter)
                if info.name != self.display_strings[num] or is_button != self.display_kind[num] or is_enabled != self.display_enabled[num]:
                    self._reset_display_tasks[num].kill()
                    sysex = MTSysex()
                    sysex.deviceParameterNamesMessage(info.name, is_button, num, is_enabled)
                    sysex.send()
                    self.display_strings[num] = info.name
                    self.display_kind[num] = is_button
                    self.display_enabled[num] = is_enabled
                    
    def _update_parameter_values(self):
        for num, info in enumerate(self.parameter_provider.parameters):
            parameter = info.parameter
            if parameter:
                if not is_parameter_button(parameter) and self.button_touch_states[num]:
                    self.show_parameter_value(num)

    @touch_button_1.pressed
    def touch_button_1(self, button):
        self.touch_button_toggle(0, button.is_pressed)
        
    @touch_button_1.released
    def touch_button_1(self, button):
        self.touch_button_toggle(0, button.is_pressed)
        
    @touch_button_1.double_clicked
    def touch_button_1(self, _):
        self.reset_parameter_to_default(0)
        
    @touch_button_2.pressed
    def touch_button_2(self, button):
        self.touch_button_toggle(1, button.is_pressed)
        
    @touch_button_2.released
    def touch_button_2(self, button):
        self.touch_button_toggle(1, button.is_pressed)
        
    @touch_button_2.double_clicked
    def touch_button_2(self, _):
        self.reset_parameter_to_default(1)

    @touch_button_3.pressed
    def touch_button_3(self, button):
        self.touch_button_toggle(2, button.is_pressed)
        
    @touch_button_3.released
    def touch_button_3(self, button):
        self.touch_button_toggle(2, button.is_pressed)
        
    @touch_button_3.double_clicked
    def touch_button_3(self, _):
        self.reset_parameter_to_default(2)
        
    @touch_button_4.pressed
    def touch_button_4(self, button):
        self.touch_button_toggle(3, button.is_pressed)
        
    @touch_button_4.released
    def touch_button_4(self, button):
        self.touch_button_toggle(3, button.is_pressed)
        
    @touch_button_4.double_clicked
    def touch_button_4(self, _):
        self.reset_parameter_to_default(3)
        
    @touch_button_5.pressed
    def touch_button_5(self, button):
        self.touch_button_toggle(4, button.is_pressed)
        
    @touch_button_5.released
    def touch_button_5(self, button):
        self.touch_button_toggle(4, button.is_pressed)
        
    @touch_button_5.double_clicked
    def touch_button_5(self, _):
        self.reset_parameter_to_default(4)
        
    @touch_button_6.pressed
    def touch_button_6(self, button):
        self.touch_button_toggle(5, button.is_pressed)
        
    @touch_button_6.released
    def touch_button_6(self, button):
        self.touch_button_toggle(5, button.is_pressed)
        
    @touch_button_6.double_clicked
    def touch_button_6(self, _):
        self.reset_parameter_to_default(5)
        
    @touch_button_7.pressed
    def touch_button_7(self, button):
        self.touch_button_toggle(6, button.is_pressed)
        
    @touch_button_7.released
    def touch_button_7(self, button):
        self.touch_button_toggle(6, button.is_pressed)
        
    @touch_button_7.double_clicked
    def touch_button_7(self, _):
        self.reset_parameter_to_default(6)
        
    @touch_button_8.pressed
    def touch_button_8(self, button):
        self.touch_button_toggle(7, button.is_pressed)
        
    @touch_button_8.released
    def touch_button_8(self, button):
        self.touch_button_toggle(7, button.is_pressed)
        
    @touch_button_8.double_clicked
    def touch_button_8(self, _):
        self.reset_parameter_to_default(7)
                
    def touch_button_toggle(self, num, is_toggled):
        self.button_touch_states[num] = is_toggled
        info = self.parameter_provider.parameters[num]
        parameter = info.parameter
        if not is_toggled:
            if parameter:
                self._reset_display_tasks[num].kill()
                self._reset_display_tasks[num] = self._tasks.add(task.sequence(task.wait(1), task.run(self.reset_display, num, info.name)))
        else:
            if not is_parameter_button(parameter):
                self.show_parameter_value(num)

    def show_parameter_value(self, num):
        if self.is_enabled():
            info = self.parameter_provider.parameters[num]
            parameter = info.parameter
            sysex = MTSysex()
            sysex.deviceParameterValue(unicode(parameter), num)
            sysex.send()
                    
    def reset_display(self, num, name):
        sysex = MTSysex()
        sysex.deviceParameterValue(name, num)
        sysex.send()

    def reset_parameter_to_default(self, num):
        info = self.parameter_provider.parameters[num]
        parameter = info.parameter
        parameter.value = parameter.default_value
        self.show_parameter_value(num)
