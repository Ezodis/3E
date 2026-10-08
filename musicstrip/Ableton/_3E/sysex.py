import Live

class MTSysex:

    @staticmethod
    def set_midi_callback(callback):
        #raise dir(callback).count('im_func') is 1 or AssertionError
        MTSysex._midi_callback = callback

    @staticmethod
    def set_log(func):
        #raise dir(func).count('im_func') is 1 or AssertionError
        MTSysex.log_message = func

    @staticmethod
    def release_attributes():
        MTSysex.log_message = None
        MTSysex._midi_callback = None

    def __init__(self):
        self._msg = [240, 126, 0]

    def msg(self):
        return tuple(self._msg + [247])
    
    def convert_7bit(self, name):
        ba = bytearray(name, 'UTF-8')
        oa = bytearray()
        shift = 1
        last = 0
        for c in ba:
            if shift == 8:
                shift = 1
                oa.append(last)
                last = 0
            o = c >> shift
            o += last
            last = c & (pow(2, shift) - 1)
            last = last << (7-shift)
            shift += 1
            oa.append(o)
        oa.append(last)
        return oa
    
    def colorMessage(self, color):
        r = color>>16
        g = (color>>8)-(r<<8)
        b = color - ((color>>8)<<8)
        r = (r+1)/2-1
        g = (g+1)/2-1
        b = (b+1)/2-1
        if r<0:
            r=0
        if g<0:
            g=0
        if b<0:
            b=0
        ba = bytearray([1])
        self._msg += tuple(ba)
        self._msg += [int(r), int(g), int(b)]
        
    def deviceColorMessage(self, color):
        r = color>>16
        g = (color>>8)-(r<<8)
        b = color - ((color>>8)<<8)
        r = (r+1)/2-1
        g = (g+1)/2-1
        b = (b+1)/2-1
        if r<0:
            r=0
        if g<0:
            g=0
        if b<0:
            b=0
        ba = bytearray([4])
        self._msg += tuple(ba)
        self._msg += [int(r), int(g), int(b)]
        
    def trackNameMessage(self, name):
        ba = bytearray([0])
        ba.extend(self.convert_7bit(name))
        self._msg += tuple(ba)
        
    def panNameMessage(self, name):
        ba = bytearray([5])
        ba.extend(self.convert_7bit(name))
        self._msg += tuple(ba)
        
    def deviceNameMessage(self, name):
        ba = bytearray([3])
        ba.extend(self.convert_7bit(name))
        self._msg += tuple(ba)
        
    def sendSendMessage(self, number, name):
        ba = bytearray([2, number])
        ba.extend(self.convert_7bit(name))
        self._msg += tuple(ba)
        
    def deviceParameterNamesMessage(self, name, is_button, number, is_enabled):
        if is_enabled:
            if is_button:
                self._midi_callback(tuple([176, 20+number, 2]))
            else:
                self._midi_callback(tuple([176, 20+number, 1]))
        else:
            name = ' '
            self._midi_callback(tuple([176, 20+number, 0]))
        ba = bytearray([10, number])
        ba.extend(self.convert_7bit(name))
        self._msg += tuple(ba)
        
    def deviceParameterValue(self, name, number):
        ba = bytearray([10, number])
        ba.extend(self.convert_7bit(name))
        self._msg += tuple(ba)

    def send(self):
        if self._midi_callback is not None:
            valid = True
            if max(self.msg()[1:-2]) > 127:
                valid = False
            if valid:
                self._midi_callback(self.msg())
            else:
                self.log_message('INVALID SYSEX MESSAGE')
                
    def sendControl(self, data1, data2):
        if self._midi_callback is not None:
            self._midi_callback(tuple([176, data1, data2]))


