from __future__ import absolute_import, print_function, unicode_literals
import sys
if sys.version_info[0] == 3:
    from builtins import range
import Live
from ableton.v2.base import liveobj_valid, listens
from ableton.v2.control_surface import BankingInfo, ControlSurface, DeviceDecoratorFactory, Layer, MIDI_CC_TYPE, MIDI_PB_TYPE
from ableton.v2.control_surface.elements import ButtonElement, SliderElement, EncoderElement
from ableton.v2.control_surface.default_bank_definitions import BANK_DEFINITIONS as DEFAULT_BANK_DEFINITIONS
from ableton.v2.control_surface.device_provider import DeviceProvider
from .channelstrip import ChannelStripComponent
from .device import DeviceComponent
from .deviceparameters import DeviceParameterComponent
from .sysex import MTSysex
from .skin import skin

class MidiTouchbar(ControlSurface):

    def __init__(self, *a, **k):
        super(MidiTouchbar, self).__init__(*a, **k)
        MTSysex.set_midi_callback(self._send_midi)
        MTSysex.set_log(self.show_message)
        
        with self.component_guard():
            self._create_controls()
            self._create_channelstrip()
            self._create_device()
            self._reset_touchbar()
            self.__on_selected_track_changed()
        self.__on_selected_track_changed.subject = self.song.view
        
    def _create_controls(self):
        self._next_bank_button = ButtonElement(False, MIDI_CC_TYPE, 0, 10, name=u'Next_Bank_Button')
        self.device_on_off_button = ButtonElement(False, MIDI_CC_TYPE, 0, 11, name=u'Device_On_Button')
        self._device_open_button = ButtonElement(True, MIDI_CC_TYPE, 0, 4, name=u'Dvice_Open_Button')
        self._volume_touch = ButtonElement(True, MIDI_CC_TYPE, 0, 40, name=u'Volume_Touch')
        self._pan_touch = ButtonElement(True, MIDI_CC_TYPE, 0, 41, name=u'Pan_Touch')
        self._send_touch_1 = ButtonElement(True, MIDI_CC_TYPE, 0, 42, name=u'Send_Touch_1')
        self._send_touch_2 = ButtonElement(True, MIDI_CC_TYPE, 0, 43, name=u'Send_Touch_2')
        self._send_touch_3 = ButtonElement(True, MIDI_CC_TYPE, 0, 44, name=u'Send_Touch_3')
        self._send_touch_4 = ButtonElement(True, MIDI_CC_TYPE, 0, 45, name=u'Send_Touch_4')
        self.bank_button_1 = ButtonElement(False, MIDI_CC_TYPE, 0, 64, name=u'Bank_Button_1')
        self.bank_button_2 = ButtonElement(False, MIDI_CC_TYPE, 0, 65, name=u'Bank_Button_2')
        self.bank_button_3 = ButtonElement(False, MIDI_CC_TYPE, 0, 66, name=u'Bank_Button_3')
        self.bank_button_4 = ButtonElement(False, MIDI_CC_TYPE, 0, 67, name=u'Bank_Button_4')
        self.bank_button_5 = ButtonElement(False, MIDI_CC_TYPE, 0, 68, name=u'Bank_Button_5')
        self.bank_button_6 = ButtonElement(False, MIDI_CC_TYPE, 0, 69, name=u'Bank_Button_6')
        self.bank_button_7 = ButtonElement(False, MIDI_CC_TYPE, 0, 70, name=u'Bank_Button_7')
        self.bank_button_8 = ButtonElement(False, MIDI_CC_TYPE, 0, 71, name=u'Bank_Button_8')
        self.bank_button_9 = ButtonElement(False, MIDI_CC_TYPE, 0, 72, name=u'Bank_Button_9')
        self._touch_button_1 = ButtonElement(True, MIDI_CC_TYPE, 0, 50, name=u'Touch_Button_1')
        self._touch_button_2 = ButtonElement(True, MIDI_CC_TYPE, 0, 51, name=u'Touch_Button_1')
        self._touch_button_3 = ButtonElement(True, MIDI_CC_TYPE, 0, 52, name=u'Touch_Button_1')
        self._touch_button_4 = ButtonElement(True, MIDI_CC_TYPE, 0, 53, name=u'Touch_Button_1')
        self._touch_button_5 = ButtonElement(True, MIDI_CC_TYPE, 0, 54, name=u'Touch_Button_1')
        self._touch_button_6 = ButtonElement(True, MIDI_CC_TYPE, 0, 55, name=u'Touch_Button_1')
        self._touch_button_7 = ButtonElement(True, MIDI_CC_TYPE, 0, 56, name=u'Touch_Button_1')
        self._touch_button_8 = ButtonElement(True, MIDI_CC_TYPE, 0, 57, name=u'Touch_Button_1')

    def _create_channelstrip(self):
        self._strip = ChannelStripComponent(is_enabled=False, layer=Layer(volume_touch=self._volume_touch, pan_touch=self._pan_touch, send_touch_1=self._send_touch_1, send_touch_2=self._send_touch_2, send_touch_3=self._send_touch_3, send_touch_4=self._send_touch_4))
        self._strip.set_solo_button(ButtonElement(False, MIDI_CC_TYPE, 0, 1, skin=skin, name=u'Solo_Button'))
        self._strip.set_volume_control(SliderElement(MIDI_PB_TYPE, 0, 0, name=u'Volume_Slider'))
        self._strip.set_pan_control(SliderElement(MIDI_PB_TYPE, 1, 0, name=u'Pan_Slider'))
        sends = []
        for i in range(4):
            sends.append(SliderElement(MIDI_PB_TYPE, 2+i, 0, name=u'Send{i}_Slider'))
        self._strip.set_send_controls(sends)
        self._strip.set_mute_button(ButtonElement(False, MIDI_CC_TYPE, 0, 2, skin=skin, name=u'Mute_Button'))
        self._strip.set_enabled(True)
        
    def _create_device(self):
        DeviceProvider.device_selection_follows_track_selection = False
        self._device = DeviceComponent(is_enabled=False, device_decorator_factory=DeviceDecoratorFactory(), device_bank_registry=self._device_bank_registry, banking_info=BankingInfo(DEFAULT_BANK_DEFINITIONS), name=u'Device', layer=Layer(next_bank_button=self._next_bank_button, device_on_off_button=self.device_on_off_button, device_open_button=self._device_open_button, bank_button_1=self.bank_button_1, bank_button_2=self.bank_button_2, bank_button_3=self.bank_button_3, bank_button_4=self.bank_button_4, bank_button_5=self.bank_button_5, bank_button_6=self.bank_button_6, bank_button_7=self.bank_button_7, bank_button_8=self.bank_button_8, bank_button_9=self.bank_button_9))
        self._device_parameter = DeviceParameterComponent(is_enabled=False, parameter_provider=self._device, name=u'Device_Parameters', layer=Layer(touch_button_1=self._touch_button_1, touch_button_2=self._touch_button_2, touch_button_3=self._touch_button_3, touch_button_4=self._touch_button_4, touch_button_5=self._touch_button_5, touch_button_6=self._touch_button_6, touch_button_7=self._touch_button_7, touch_button_8=self._touch_button_8))
        params = []
        for i in range(8):
            params.append(SliderElement(MIDI_PB_TYPE, 8+i, 0, name=u'Param{i}_Slider'))
            params[i].set_report_values(True, True)
        self._device_parameter.set_parameter_controls(params)
        self._device.set_enabled(True)
        self._device_parameter.set_enabled(True)
        self._last_selected_devide = None
        self._select_device()
        
    def port_settings_changed(self):
        super(MidiTouchbar, self).port_settings_changed()
        self._reset_touchbar()
        self._device_parameter.clear_display()
        self.__on_selected_track_changed()
        self._select_device()

    @listens(u'selected_track')
    def __on_selected_track_changed(self):
        track = self.song.view.selected_track
        self._strip.set_track(track)
        self.__on_selected_device_changed.subject = track.view
        self._select_device()
            
    @listens(u'selected_device')
    def __on_selected_device_changed(self):
        device = self.song.view.selected_track.view.selected_device
        if device != None:
            self._select_device()
        else:
            self._device.set_device(None)
        
    def _select_device(self):
        track = self.song.view.selected_track
        device_to_select = track.view.selected_device
        if device_to_select == None and len(track.devices) > 0:
            device_to_select = track.devices[0]
        if device_to_select != None:
            self._device.set_device(device_to_select)
            self._last_selected_devide = device_to_select
        elif not liveobj_valid(self._last_selected_devide):
            self._device.set_device(None)
            
    def _reset_touchbar(self):
        self._send_midi(tuple([176, 28, 0]));
        self._send_midi(tuple([176, 29, 0]));
        self._send_midi(tuple([176, 30, 0]));
        self._send_midi(tuple([176, 3, 0]));

