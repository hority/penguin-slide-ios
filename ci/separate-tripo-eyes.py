"""Build independent glossy eye shells over the original Tripo face with restored skin textures.
Usage: python ci/separate-tripo-eyes.py PRE_EYE_MODELS OUTPUT_MODELS
Writes the same body/eyeL/eyeR STG2 groups used by existing characters. Eyes match the measured pupil positions and outlines; the shared atlas includes
repaired skin and glossy black/white eye colors.
"""
from pathlib import Path
import json,struct,sys,math,numpy as np
from PIL import Image
source,out=map(Path,sys.argv[1:3])
SETTINGS={'rabbit':(.095,.395,.041,.047),'dolphinchibi':(.115,.44,.045,.052),'rhino':(.12,.40,.049,.058),'orca':(.102,.44,.043,.050)}
def smooth(a,b,x):
 t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
def sphere(center,radii,rings,segments,tex):
 vertices=[center+np.array([0,0,radii[2]])];normals=[np.array([0,0,1])]
 for j in range(1,rings):
  phi=math.pi*j/rings
  for k in range(segments):
   angle=2*math.pi*k/segments;unit=np.array([math.sin(phi)*math.cos(angle),math.sin(phi)*math.sin(angle),math.cos(phi)])
   vertices.append(center+radii*unit);normal=unit/radii;normals.append(normal/np.linalg.norm(normal))
 vertices.append(center-np.array([0,0,radii[2]]));normals.append(np.array([0,0,-1]));faces=[]
 for k in range(segments):faces.append((0,1+k,1+(k+1)%segments))
 for j in range(rings-2):
  for k in range(segments):
   a=1+j*segments+k;b=1+j*segments+(k+1)%segments;c=a+segments;d=b+segments;faces.extend([(a,c,b),(b,c,d)])
 last=len(vertices)-1;start=1+(rings-2)*segments
 for k in range(segments):faces.append((last,start+(k+1)%segments,start+k))
 unit=(np.array(vertices)-center)/radii
 uv=np.stack([tex[0]+.015*np.arctan2(unit[:,1],unit[:,0])/math.pi,tex[1]+.015*(np.arccos(np.clip(unit[:,2],-1,1))/math.pi-.5)],1)
 return np.array(vertices),np.array(normals),uv,np.array(faces)
for name,(ex,ey,rx,ry) in SETTINGS.items():
 d=(source/(name.capitalize()+'.bin')).read_bytes();nv,ni=struct.unpack_from('<II',d,20);p=np.frombuffer(d,'<f4',nv*3,28).reshape(-1,3).copy();n=np.frombuffer(d,'<f4',nv*3,28+nv*12).reshape(-1,3).copy();uv=np.frombuffer(d,'<f4',nv*2,28+nv*24).reshape(-1,2).copy();ix=np.frombuffer(d,'<u4',ni,28+nv*32).reshape(-1,3).copy()
 base=np.array(Image.open(source/(name+'_base.jpg')).convert('RGB'),dtype=float);size=base.shape[0];world=np.full((size,size,3),np.nan)
 # Rasterize geometry positions in the existing atlas, so only eye skin changes.
 for t in ix:
  q=uv[t]*size;lo=np.maximum(np.floor(q.min(0)).astype(int),0);hi=np.minimum(np.ceil(q.max(0)).astype(int),size-1)
  if (hi<lo).any():continue
  xs,ys=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5);v0=q[1]-q[0];v1=q[2]-q[0];det=v0[0]*v1[1]-v0[1]*v1[0]
  if abs(det)<1e-9:continue
  vx=xs-q[0,0];vy=ys-q[0,1];b=(vx*v1[1]-vy*v1[0])/det;c=(v0[0]*vy-v0[1]*vx)/det;mask=(b>=0)&(c>=0)&(b+c<=1)
  w=p[t[0]]+(p[t[1]]-p[t[0]])*b[...,None]+(p[t[2]]-p[t[0]])*c[...,None];block=world[lo[1]:hi[1]+1,lo[0]:hi[0]+1];block[mask]=w[mask]
 clean=base.copy();skinmask=np.zeros((size,size));body=p.copy();body_normals=n.copy();groups={};body_uv=uv.copy();body_ix=ix.copy();skincolors=[];skinramps=[]
 for side,label in [(-1,'eyeL'),(1,'eyeR')]:
  dx=(p[:,0]-side*ex)/rx;dy=(p[:,1]-ey)/ry;r=np.hypot(dx,dy);front=p[:,2]>.10
  # Fit a smooth skin surface to the ring surrounding each raised eye.
  ring=(r>1.22)&(r<1.8)&front
  x=p[ring,0]-side*ex;y=p[ring,1]-ey;design=np.stack([np.ones(len(x)),x,y,x*x,x*y,y*y],1)
  coeff=np.linalg.lstsq(design,p[ring,2],rcond=None)[0];x=p[:,0]-side*ex;y=p[:,1]-ey;surface=np.stack([np.ones(len(x)),x,y,x*x,x*y,y*y],1)@coeff
  # Smooth fused socket relief with a monotone depth deformation. Retaining
  # 15% of depth separation avoids coincident layers and self-shadow artifacts.
  w=(1-smooth(.9,1.3,r))*front;factor=.85
  x=p[:,0]-side*ex;y=p[:,1]-ey;t=np.clip((r-.9)/.4,0,1);dwdr=-6*t*(1-t)/.4
  wx=dwdr*x/(rx*rx*np.maximum(r,1e-8))*front;wy=dwdr*y/(ry*ry*np.maximum(r,1e-8))*front
  sx=coeff[1]+2*coeff[3]*x+coeff[4]*y;sy=coeff[2]+coeff[4]*x+2*coeff[5]*y
  jz=1-factor*w;jx=factor*(w*sx+(surface-p[:,2])*wx);jy=factor*(w*sy+(surface-p[:,2])*wy)
  body[:,2]+=factor*w*(surface-p[:,2])
  nn=np.stack([n[:,0]-jx*n[:,2]/jz,n[:,1]-jy*n[:,2]/jz,n[:,2]/jz],1);nn/=np.linalg.norm(nn,axis=1,keepdims=True)
  body_normals[w>0]=nn[w>0]
  # Tripo fused the eye rims to the face. Rebuild smooth glossy eye shells at
  # the measured pupil positions; they use the app's existing eye-node rig.
  center=np.array([side*ex,ey,np.max(p[(r<.8)&front,2])+.004])
  pieces=[sphere(center,np.array([rx*.80,ry*.80,.021]),8,16,(.25,.125)),
          sphere(center+np.array([-.010,.016,.020]),np.array([.008,.009,.003]),4,8,(.25,.375)),
          sphere(center+np.array([.009,-.012,.020]),np.array([.003,.004,.002]),4,8,(.25,.375))]
  pp=[];nn=[];tt=[];ii=[];offset=0
  for vp,vn,vt,vi in pieces:pp.append(vp);nn.append(vn);tt.append(vt);ii.append(vi+offset);offset+=len(vp)
  groups[label]=(np.concatenate(pp),np.concatenate(nn),np.concatenate(tt),np.concatenate(ii))
  dx=(world[:,:,0]-side*ex)/rx;dy=(world[:,:,1]-ey)/ry;radius=np.hypot(dx,dy);front=world[:,:,2]>.10
  ring=(radius>1.3)&(radius<1.7)&front
  samples=base[ring]
  if name=='orca':samples=samples[np.mean(samples,1)<np.percentile(np.mean(samples,1),40)]
  elif name in ['rabbit','rhino']:samples=samples[np.max(samples,1)-np.min(samples,1)<45]
  color=np.median(samples,axis=0);skincolors.append(tuple(np.uint8(color)))
  ramp=[]
  for row in range(size//4):
   y=ey+(.125-(row+.5)/size)/1.5
   nearby=base[ring & (np.abs(world[:,:,1]-y)<.012)]
   if len(nearby):
    if name=='orca':nearby=nearby[np.mean(nearby,1)<=np.percentile(np.mean(nearby,1),40)]
    elif name in ['rabbit','rhino']:nearby=nearby[np.max(nearby,1)-np.min(nearby,1)<45]
    else:nearby=nearby[~((nearby[:,0]>nearby[:,1]*1.1)&(nearby[:,0]-nearby[:,2]>40))]
   ramp.append(np.median(nearby,axis=0) if len(nearby) else color)
  skinramps.append(np.uint8(np.clip(ramp,0,255)))
  mask=np.nan_to_num((1-smooth(1.12,1.42,radius))*front)
  row=np.clip(np.nan_to_num((.125-(world[:,:,1]-ey)*1.5)*size),0,size//4-1).astype(int)
  skin=skinramps[-1][row]
  clean=clean*(1-mask[...,None])+skin*mask[...,None];skinmask=np.maximum(skinmask,mask)
 bodyuv=body_uv.copy();bodyuv[:,0]=.5+.5*bodyuv[:,0]
 groups['body']=(body,body_normals,bodyuv,body_ix)
 # Original left half (eyes), clean right half (skin): one material, as in the app.
 for suffix in ['base.jpg','normal.png','rough.png']:
  original=Image.open(source/(name+'_'+suffix)).convert('RGB');sz=original.height
  if suffix=='base.jpg':repaired=Image.fromarray(np.uint8(np.clip(clean,0,255)))
  else:
   a=np.array(original,dtype=float);mask=np.array(Image.fromarray(np.uint8(skinmask*255)).resize((sz,sz),Image.Resampling.BILINEAR))/255
   fill=np.array([128,128,255]) if suffix=='normal.png' else np.array([150]*3)
   repaired=Image.fromarray(np.uint8(a*(1-mask[...,None])+fill*mask[...,None]))
  atlas=Image.new('RGB',(sz,sz))
  colors=[(8,10,14),(245,249,255)]+skincolors
  for j,color in enumerate(colors):
   fill=color if suffix=='base.jpg' else ((128,128,255) if suffix=='normal.png' else ((60,60,60) if j<2 else (150,150,150)))
   atlas.paste(fill,(0,j*sz//4,sz//2,(j+1)*sz//4))
  if suffix=='base.jpg':
   for j,ramp in enumerate(skinramps):atlas.paste(Image.fromarray(np.repeat(ramp[:,None,:],sz//2,axis=1)),(0,(j+2)*sz//4))
  atlas.paste(repaired.resize((sz//2,sz),Image.Resampling.LANCZOS),(sz//2,0));atlas.save(out/(name+'_'+suffix),quality=92)
 with open(out/(name.capitalize()+'.bin'),'wb') as f:
  header=b'{}';f.write(b'STG2'+struct.pack('<I',2)+header+struct.pack('<I',len(groups)))
  for label,(pos,norm,tex,tri) in sorted(groups.items()):
   f.write(struct.pack('<H',len(label))+label.encode()+struct.pack('<II',len(pos),tri.size));f.write(pos.astype('<f4').tobytes()+norm.astype('<f4').tobytes()+tex.astype('<f4').tobytes()+tri.astype('<u4').tobytes())
 print(name,{label:len(g[3]) for label,g in groups.items()})
