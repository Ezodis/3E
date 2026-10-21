import itertools, plistlib, subprocess, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[3]
source=root/'TouchBar/build/threee/3E.app'
script=root/'TouchBar/threee/Source/Resources/ConfigureModules.sh'
modules={'touchbar':'Contents/Helpers/MIDI Touchbar.app','touchtab':'Contents/Frameworks/ThreeEGestureEngine.dylib','phone':'Contents/Resources/PhoneControl'}
with tempfile.TemporaryDirectory(prefix='threee-module-test-') as directory:
    app=Path(directory)/'3E.app'
    for selection in [(),('touchbar',),('touchtab',),('phone',),('touchbar','touchtab'),('touchbar','phone'),('touchtab','phone'),tuple(modules)]:
        subprocess.run(['ditto',str(source),str(app)],check=True,stdout=subprocess.DEVNULL)
        result=subprocess.run(['zsh',str(script),str(app),','.join(selection)],capture_output=True,text=True)
        assert result.returncode==0,(selection,result.stderr)
        info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        assert set(info['ThreeEModules'])==set(selection)
        assert info['CFBundleIdentifier']=='local.musicstrip.app'
        assert info['ThreeEIncludesTouchTab']==('touchtab' in selection)
        for module,payload in modules.items(): assert (app/payload).exists()==(module in selection),(selection,module)
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
        print('Verified signed selection:',selection,flush=True)
        import shutil
        shutil.rmtree(app)
    subprocess.run(['ditto',str(source),str(app)],check=True)
    before=(app/'Contents/Info.plist').read_bytes()
    result=subprocess.run(['zsh',str(script),str(app),'invalid'],capture_output=True)
    assert result.returncode!=0 and (app/'Contents/Info.plist').read_bytes()==before
    print('Unknown module refused before mutation',flush=True)
