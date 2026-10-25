"""Validate actual STG2 payloads and texture files without SceneKit (Python + Pillow + numpy)."""
from pathlib import Path
import json,struct,numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1]/'HelloFlight'; reports=[]
for name in ['rabbit','dolphinchibi','rhino','orca']:
 path=root/'Models'/(name.capitalize()+'.bin');d=path.read_bytes();assert d[:4]==b'STG2';o=4
 n,=struct.unpack_from('<I',d,o);o+=4;header=json.loads(d[o:o+n]);o+=n
 count,=struct.unpack_from('<I',d,o);o+=4;triangles=vertices=0;positions=[];groups=[]
 for _ in range(count):
  n,=struct.unpack_from('<H',d,o);o+=2;group=d[o:o+n].decode();o+=n;groups.append(group)
  v,i=struct.unpack_from('<II',d,o);o+=8;assert v>0 and i%3==0
  p=np.frombuffer(d,'<f4',v*3,o).reshape(-1,3);o+=v*12
  normals=np.frombuffer(d,'<f4',v*3,o).reshape(-1,3);o+=v*12
  uv=np.frombuffer(d,'<f4',v*2,o).reshape(-1,2);o+=v*8
  ix=np.frombuffer(d,'<u4',i,o).reshape(-1,3);o+=i*4
  assert np.isfinite(p).all() and np.isfinite(normals).all() and np.isfinite(uv).all()
  assert ix.max()<v and np.allclose(np.linalg.norm(normals,axis=1),1,atol=.015)
  assert ((uv>=-.001)&(uv<=1.001)).all()
  assert np.linalg.norm(np.cross(p[ix[:,1]]-p[ix[:,0]],p[ix[:,2]]-p[ix[:,0]]),axis=1).min()>1e-12
  if group in header.get('weights',[]):o+=v*8
  triangles+=i//3;vertices+=v;positions.append(p)
 assert o==len(d) and set(groups)=={'body','eyeL','eyeR'} and 6000<=triangles<=9300
 p=np.concatenate(positions);assert abs(p[:,1].min())<1e-5 and .69<=p[:,1].max()<=.79
 for suffix,size in [('base.jpg',1024),('normal.png',512),('rough.png',512)]:
  im=Image.open(root/'Models'/(name+'_'+suffix));im.load();assert im.size==(size,size)
 im=Image.open(root/'Illustrations'/(('rabbitchibi' if name=='rabbit' else name)+'.png'));im.load();assert im.mode=='RGBA' and im.getchannel('A').getextrema()==(0,255)
 reports.append(dict(name=name,triangles=triangles,vertices=vertices,mesh_bytes=len(d),height=float(p[:,1].max())))
print(json.dumps({'passed':True,'assets':reports},indent=2))
