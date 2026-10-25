"""Bake closed-eye atlases from each runtime mesh; leaves geometry and original atlases intact."""
import struct,numpy as np
from PIL import Image
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'HelloFlight/Models'
for name,(ex,ey,rx,ry) in {'rabbit':(.095,.395,.044,.051),'dolphinchibi':(.115,.44,.046,.054),'rhino':(.12,.40,.051,.058),'orca':(.11,.43,.047,.052)}.items():
 d=(root/(name.capitalize()+'.bin')).read_bytes();nv,ni=struct.unpack_from('<II',d,20);p=np.frombuffer(d,'<f4',nv*3,28).reshape(-1,3);uv=np.frombuffer(d,'<f4',nv*2,28+nv*24).reshape(-1,2);ix=np.frombuffer(d,'<u4',ni,28+nv*32).reshape(-1,3)
 a=np.array(Image.open(root/(name+'_base.jpg')).convert('RGB'),dtype=float);size=a.shape[0];world=np.full((size,size,3),np.nan)
 for t in ix:
  q=uv[t]*size;lo=np.maximum(np.floor(q.min(0)).astype(int),0);hi=np.minimum(np.ceil(q.max(0)).astype(int),size-1)
  if (hi<lo).any():continue
  xs,ys=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5);v0=q[1]-q[0];v1=q[2]-q[0];det=v0[0]*v1[1]-v0[1]*v1[0]
  if abs(det)<1e-9:continue
  vx=xs-q[0,0];vy=ys-q[0,1];b=(vx*v1[1]-vy*v1[0])/det;c=(v0[0]*vy-v0[1]*vx)/det;mask=(b>=0)&(c>=0)&(b+c<=1)
  w=p[t[0]]+(p[t[1]]-p[t[0]])*b[...,None]+(p[t[2]]-p[t[0]])*c[...,None];block=world[lo[1]:hi[1]+1,lo[0]:hi[0]+1];block[mask]=w[mask]
 for side in [-1,1]:
  dx=(world[:,:,0]-side*ex)/rx;dy=(world[:,:,1]-ey)/ry;r=np.sqrt(dx*dx+dy*dy);front=world[:,:,2]>.10
  ring=(r>1.08)&(r<1.4)&front
  # Use upper/lower neighbouring skin colours; dolphin eyes cross the cream/blue boundary.
  colors=[]
  for upper in [False,True]:
   sample=a[ring & ((dy>0) if upper else (dy<=0))];colors.append(np.median(sample,axis=0) if len(sample) else np.array([180]*3))
  if name=='orca':
   samples=a[ring];dark=samples[np.mean(samples,axis=1)<=np.percentile(np.mean(samples,axis=1),35)];colors=[np.median(dark,axis=0)]*2
  blend=np.clip((dy+.6)/1.2,0,1);skin=colors[0]*(1-blend[...,None])+colors[1]*blend[...,None]
  mask=np.clip((1.08-r)/.16,0,1)*front;mask=np.nan_to_num(mask);a=a*(1-mask[...,None])+np.nan_to_num(skin)*mask[...,None]
  line=(np.abs(world[:,:,1]-(ey-.006+.006*dx*dx))<.0025)&(np.abs(dx)<.78)&front
  a[line]=[28,25,30]
 Image.fromarray(np.uint8(np.clip(a,0,255))).save(root/(name+'_blink.jpg'),quality=92)
