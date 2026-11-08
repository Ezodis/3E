# Upgrade existing song-bank racks in place; no audio or new scenes are created.
from pathlib import Path
import gzip, copy, xml.etree.ElementTree as E
import argparse
parser=argparse.ArgumentParser(description="Add NOTA and RUFF hold modes to an existing song-bank set. Quit Live first.")
parser.add_argument("set", type=Path)
p=parser.parse_args().set
r=E.fromstring(gzip.decompress(p.read_bytes()));s=r.find('LiveSet')
def unique(n):return n.get('Id') is not None and (n.tag.endswith('Target') or n.tag=='Pointee' or n.tag.startswith('ControllerTargets.'))
uid=max(int(n.get('Id')) for n in r.iter() if unique(n))+100

def v(n,path,value):
 e=n.find(path);assert e is not None,path
 e.set('Value',str(value).lower() if isinstance(value,bool) else str(value))
def clone(n):
 global uid
 n=copy.deepcopy(n);mapping={}
 for e in n.iter():
  if unique(e):mapping[e.get('Id')]=str(uid);e.set('Id',str(uid));uid+=1
 for e in n.iter():
  if e.tag=='PointeeId' and e.get('Value') in mapping:e.set('Value',mapping[e.get('Value')])
 for parent in n.iter():
  for e in list(parent):
   if e.tag=='KeyMidi':parent.remove(e)
 return n
bank=s.findall('Tracks/MidiTrack')[1].find('DeviceChain/DeviceChain/Devices/InstrumentGroupDevice')
for index,name in [(1,'RUFF'),(2,'NOTA')]:
 rack=bank.find('Branches')[index].find('.//InstrumentGroupDevice');branches=rack.find('Branches')
 if rack.find('UserName').get('Value','').endswith(' | 3 '+name):continue
 assert len(branches)==4,'Unexpected mode rack structure'
 plain=branches[0];arp=rack.find('.//MidiArpeggiator');instrument=plain.find('.//OriginalSimpler');chord=plain.find('.//MidiChord')
 def add(label,devices):
  b=clone(plain);b.set('Id',str(len(branches)))
  for k in ['EffectiveName','UserName']:v(b,'Name/'+k,label)
  for k in ['Min','Max','CrossfadeMin','CrossfadeMax']:v(b,'BranchSelectorRange/'+k,3)
  v(b,'MixerDevice/Volume/Manual',1)
  ds=b.find('DeviceChain/MidiToAudioDeviceChain/Devices');ds.clear()
  for i,d in enumerate(devices):d.set('Id',str(i));ds.append(d)
  branches.append(b)
 def pulse(rate):
  d=clone(arp)
  for k,x in [('Mode',0),('SyncedRate',rate),('SyncState',True),('Hold',False),('Gate',28),('Retrigger',2),('PatternOffset',0),('Groove',0)]:v(d,k+'/Manual',x)
  return d
 def tone(low=False):
  d=clone(instrument);v(d,'VolumeAndPan/Volume/Manual',-6)
  if low:v(d,'Pitch/TransposeKey/Manual',float(d.find('Pitch/TransposeKey/Manual').get('Value'))-12)
  v(d,'VolumeAndPan/Envelope/ReleaseTime/Manual',75)
  return d
 if name=='RUFF':
  a=pulse(6);v(a,'Mode/Manual',2);v(a,'PatternOffset/Manual',2);v(a,'Gate/Manual',65)
  v(a,'UserName','RUFF - high middle low middle picking')
  add('3 RUFF Picking',[clone(chord),a,tone()])
 else:
  delay=clone(rack.find('.//Delay'));v(delay,'UserName','NOTA - chord on the half beat')
  for k,x in [('On',True),('DelayLine_SyncedSixteenthL',1),('DelayLine_SyncedSixteenthR',1),('DryWet',1),('Feedback',0)]:v(delay,k+'/Manual',x)
  add('3 NOTA - low on beat',[pulse(10),tone(True)])
  add('3 NOTA - chord off beat',[pulse(10),clone(chord),tone(),delay])
 v(rack,'UserName','MODE: 0 Plain | 1 Arp | 2 Bounce | 3 '+name)
 v(rack,'ChainSelector/Manual',3)
 v(rack,'Annotation', 'Hold one scale key. '+('High-middle-low-middle sixteenth picking, adjustable in Arpeggiator; source-inspired, not an exact transcription.' if name=='RUFF' else 'Low root every beat, chord half a beat later. Tap gives one pair; hold repeats.'))
v(s,'NextPointeeId',uid+100)
ids=[n.get('Id') for n in r.iter() if unique(n)];assert len(ids)==len(set(ids))
assert set(map(len,r.findall('.//ClipSlotList')))=={0,8}
p.write_bytes(gzip.compress(E.tostring(r,encoding='utf-8',xml_declaration=True)))
print('Updated existing set: NOTA alternating beat, RUFF picking. All scene counts and IDs valid.')
