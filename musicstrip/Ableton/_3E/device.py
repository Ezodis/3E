from __future__ import absolute_import, print_function, unicode_literals
import Live
from ableton.v2.base import liveobj_valid, listens, clamp
from ableton.v2.control_surface import ParameterInfo
from ableton.v2.control_surface.components import DeviceComponent as DeviceComponentBase
from ableton.v2.control_surface.control import ButtonControl, ToggleButtonControl
from .sysex import MTSysex

class DeviceComponent(DeviceComponentBase):
    __events__ = (u'bank',)
    next_bank_button = ButtonControl()
    device_on_off_button = ToggleButtonControl()
    device_open_button = ButtonControl()
    bank_button_1 = ButtonControl()
    bank_button_2 = ButtonControl()
    bank_button_3 = ButtonControl()
    bank_button_4 = ButtonControl()
    bank_button_5 = ButtonControl()
    bank_button_6 = ButtonControl()
    bank_button_7 = ButtonControl()
    bank_button_8 = ButtonControl()
    bank_button_9 = ButtonControl()

    def __init__(self, *a, **k):
        super(DeviceComponent, self).__init__(*a, **k)
        self.__on_bank_changed.subject = self._device_bank_registry
        
    def _create_parameter_info(self, parameter, name):
        return ParameterInfo(parameter=parameter, name=name, default_encoder_sensitivity=1.0)
        
    def set_device(self, device):
        super(DeviceComponent, self).set_device(device)
        if device != None:
            self._sendName()
            self._sendColor()
            sysex = MTSysex()
            sysex.sendControl(3, 1)
            self.update_bank_display()
            self.__on_device_on_off_changed.subject = self._on_off_parameter()
            self._update_device_on_off_button()
            self.__on_devide_name_changed.subject = device
            self.__on_track_color_changed.subject = device.canonical_parent
        else:
            sysex = MTSysex()
            sysex.sendControl(3, 0)
            self.__on_track_color_changed.subject = None
        
    def _sendName(self):
        sysex = MTSysex()
        sysex.deviceNameMessage(self._device_provider.device.name)
        sysex.send()
        
    def _sendColor(self):
        sysex = MTSysex()
        sysex.deviceColorMessage(self._device_provider.device.canonical_parent.color)
        sysex.send()
        
    @listens(u'name')
    def __on_devide_name_changed(self):
        self._sendName()
        
    @listens(u'color')
    def __on_track_color_changed(self):
        self._sendColor()
        
    @listens(u'device_bank')
    def __on_bank_changed(self, device, bank):
        if device == self.device():
            self._set_bank_index(bank)
            self.update_bank_display()
        self.notify_bank()
        
    @listens(u'value')
    def __on_device_on_off_changed(self):
        self._update_device_on_off_button()
        
    @next_bank_button.pressed
    def next_bank_button(self, _):
        self.next_bank_button._release_button()
        if self._bank:
            new_index = self._bank.index + 1
            if new_index >= self._bank.bank_count():
                new_index = 0
            self.__set_bank_index(new_index)
            
    def _update_device_on_off_button(self):
        parameter = self._on_off_parameter()
        self.device_on_off_button.enabled = parameter is not None
        if parameter is not None:
            self.device_on_off_button.is_toggled = parameter.value > 0
            
    @device_on_off_button.pressed
    def device_on_off_button(self, _):
        parameter = self._on_off_parameter()
        if parameter is not None:
            parameter.value = float(not parameter.value)
            
    def _on_off_parameter(self):
        if liveobj_valid(self.device()):
            for p in self.device().parameters:
                if p.name.startswith(u'Device On') and liveobj_valid(p) and p.is_enabled:
                    return p
                    
    @device_open_button.pressed
    def device_open_button(self, _):
        pass
        
    def __set_bank_index(self, index):
        self._device_bank_registry.set_device_bank(self.device(), index)
        self._set_bank_index(index)
            
    @bank_button_1.pressed
    def bank_button_1(self, _):
        self.__set_bank_index(0)

    @bank_button_2.pressed
    def bank_button_2(self, _):
        self.__set_bank_index(1)
        
    @bank_button_3.pressed
    def bank_button_3(self, _):
        self.__set_bank_index(2)
        
    @bank_button_4.pressed
    def bank_button_4(self, _):
        self.__set_bank_index(3)
        
    @bank_button_5.pressed
    def bank_button_5(self, _):
        self.__set_bank_index(4)
        
    @bank_button_6.pressed
    def bank_button_6(self, _):
        self.__set_bank_index(5)
        
    @bank_button_7.pressed
    def bank_button_7(self, _):
        self.__set_bank_index(6)
        
    @bank_button_8.pressed
    def bank_button_8(self, _):
        self.__set_bank_index(7)
        
    @bank_button_9.pressed
    def bank_button_9(self, _):
        self.__set_bank_index(8)

    def update_bank_display(self):
        bank_index = 0
        if self._bank.bank_count() > 1:
            bank_index = self._bank.index + 1
        sysex = MTSysex()
        sysex.sendControl(31, bank_index)
