from pathlib import Path
import struct,sys,plistlib,json
app=Path(sys.argv[1]);rows=[];errors=[]
def inspect(b,p,base=0):
 if len(b)<32:return
 magic=struct.unpack_from('<I',b)[0]
 if magic in (0xbebafeca,0xbfbafeca):
  n=struct.unpack_from('>I',b,4)[0];wide=magic==0xbfbafeca
  for i in range(n):
   at=8+i*(32 if wide else 20);off,size=struct.unpack_from('>QQ' if wide else '>II',b,at+8);inspect(b[off:off+size],p,off)
  return
 if magic!=0xfeedfacf:return
 n=struct.unpack_from('<I',b,16)[0];pos=32
 for _ in range(n):
  cmd,sz=struct.unpack_from('<II',b,pos)
  assert sz>=8 and pos+sz<=len(b),(p,pos)
  if cmd==0x32:
   platform,minimum=struct.unpack_from('<II',b,pos+8)
   version=(minimum>>16,(minimum>>8)&255,minimum&255)
   rows.append({'path':str(p.relative_to(app)),'platform':platform,'minimum':version})
   if platform==2 and version>(16,2,0):errors.append(f'{p}: minimum {version}')
  if cmd==0x21 and struct.unpack_from('<I',b,pos+16)[0]:errors.append(f'{p}: encrypted executable')
  pos+=sz
for p in app.rglob('*'):
 if p.is_file() and not p.is_symlink():
  with p.open('rb') as f:magic=f.read(4)
  if magic in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xca\xfe\xba\xbf'):inspect(p.read_bytes(),p)
  if p.name=='Info.plist':
   info=plistlib.loads(p.read_bytes());minimum=info.get('MinimumOSVersion')
   if minimum and 'Watch' not in p.relative_to(app).parts and tuple(map(int,minimum.split('.')))>(16,2):errors.append(f'{p}: plist minimum {minimum}')
(app.parent/'ios16-binaries.json').write_text(json.dumps(rows,indent=2))
print('Mach-O slices checked:',len(rows));print('\n'.join(errors));assert not errors
