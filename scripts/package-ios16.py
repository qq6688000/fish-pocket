from pathlib import Path
import zipfile,plistlib,stat,json,subprocess
root=Path(__file__).resolve().parent.parent
products=root/'app/build/DerivedData/Build/Products/Release-iphoneos'
apps=list(products.glob('*.app'))
assert len(apps)==1,apps
app=apps[0]
subprocess.run(['python3',str(root/'scripts/verify-ios16.py'),str(app)],check=True)
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['MinimumOSVersion']=='16.2',info.get('MinimumOSVersion')
metadata={'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'minimumOS':info['MinimumOSVersion'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion']}
(app/'ios16-build.json').write_text(json.dumps(metadata,indent=2))
out=root/'FishPocket-1.2-ios16.ipa'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(app.rglob('*')):
  if p.is_dir(): continue
  rel='Payload/'+str(p.relative_to(app.parent))
  zi=zipfile.ZipInfo(rel);zi.create_system=3;zi.compress_type=zipfile.ZIP_DEFLATED
  if p.is_symlink():
   zi.external_attr=(stat.S_IFLNK|0o777)<<16
   import os
   z.writestr(zi,os.readlink(p))
  else:
   zi.external_attr=(stat.S_IFREG|(p.stat().st_mode&0o777))<<16
   z.writestr(zi,p.read_bytes())
with zipfile.ZipFile(out) as z: assert z.testzip() is None
print(json.dumps(metadata,indent=2));print(out,out.stat().st_size)
