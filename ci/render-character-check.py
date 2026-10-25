"""Render the actual STG2 meshes using the app's eye scaling and pose weights.
blender -b --python ci/render-character-check.py -- MODELS OUTPUT [--export]
"""
import bpy,numpy as np,struct,json,sys,os,math
from mathutils import Matrix,Vector
args=sys.argv[sys.argv.index('--')+1:];models,out=args[:2];os.makedirs(out,exist_ok=True)
def smooth(a,b,x):
 t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
def read(name):
 d=open(os.path.join(models,name.capitalize()+'.bin'),'rb').read();o=4;n,=struct.unpack_from('<I',d,o);o+=4;h=json.loads(d[o:o+n]);o+=n;count,=struct.unpack_from('<I',d,o);o+=4;groups={}
 for _ in range(count):
  n,=struct.unpack_from('<H',d,o);o+=2;label=d[o:o+n].decode();o+=n;v,i=struct.unpack_from('<II',d,o);o+=8;p=np.frombuffer(d,'<f4',v*3,o).reshape(-1,3).copy();o+=v*12;n=np.frombuffer(d,'<f4',v*3,o).reshape(-1,3).copy();o+=v*12;uv=np.frombuffer(d,'<f4',v*2,o).reshape(-1,2).copy();o+=v*8;ix=np.frombuffer(d,'<u4',i,o).reshape(-1,3);o+=i*4
  weights=None
  if label in h.get('weights',[]):weights=np.frombuffer(d,'<f4',v*2,o).reshape(-1,2);o+=v*8
  groups[label]=(p,n,uv,ix,weights)
 return groups
def build(name,blink=0,pose=False):
 mat=bpy.data.materials.new(name);mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;bsdf=nodes.get('Principled BSDF')
 for suffix,socket in [('base.jpg','Base Color'),('normal.png','Normal'),('rough.png','Roughness')]:
  image=bpy.data.images.load(os.path.join(models,name+'_'+suffix));image.pack();tex=nodes.new('ShaderNodeTexImage');tex.image=image
  if socket!='Base Color':image.colorspace_settings.name='Non-Color'
  if socket=='Normal':
   node=nodes.new('ShaderNodeNormalMap');node.inputs['Strength'].default_value=1 if name=='penguin' else 0;links.new(tex.outputs['Color'],node.inputs['Color']);links.new(node.outputs['Normal'],bsdf.inputs['Normal'])
  else:links.new(tex.outputs['Color'],bsdf.inputs[socket])
 result=[];neck=.34 if name=='penguin' else (.30 if name=='dolphinchibi' else .28);shoulder=.165 if name=='penguin' else (.19 if name=='rhino' else .16);hp=np.array([0,neck,-.01 if name=='penguin' else 0]);headrot=np.array(Matrix.Rotation(.6 if pose else 0,3,'Y') @ Matrix.Rotation(-.4 if pose else 0,3,'X'))
 for label,(p,n,uv,ix,w) in read(name).items():
  if label.startswith('eye'):
   center=(p.min(0)+p.max(0))/2;p[:,1]=center[1]+(p[:,1]-center[1])*max(.08,1-blink);n[:,1]/=max(.08,1-blink);n/=np.linalg.norm(n,axis=1,keepdims=True)
  if label=='body' and pose:
   if w is None:
    head=smooth(neck-.025,neck+.025,p[:,1]);arm=smooth(shoulder,shoulder+.055,abs(p[:,0]))*smooth(.10,.18,p[:,1])*(1-head);head*=1-arm
   else:head,arm=w.T
   q=p.copy();qn=n.copy()
   for side in [-1,1]:
    mask=(p[:,0]<0) if side<0 else (p[:,0]>=0);ap=np.array([shoulder*side,.28 if name=='penguin' else .23,0]);rot=np.array(Matrix.Rotation(side*1.0,3,'Z'));q[mask]=p[mask]*(1-head[mask,None]-arm[mask,None])+((p[mask]-hp)@headrot.T+hp)*head[mask,None]+((p[mask]-ap)@rot.T+ap)*arm[mask,None]
    qn[mask]=n[mask]*(1-head[mask,None]-arm[mask,None])+(n[mask]@headrot.T)*head[mask,None]+(n[mask]@rot.T)*arm[mask,None]
   p=q;n=qn/np.maximum(np.linalg.norm(qn,axis=1,keepdims=True),1e-8)
  elif label!='body':p=(p-hp)@headrot.T+hp;n=n@headrot.T
  coords=np.stack([p[:,0],-p[:,2],p[:,1]],1);mesh=bpy.data.meshes.new(label);mesh.from_pydata(coords.tolist(),[],ix.tolist());mesh.update();mesh.materials.append(mat);layer=mesh.uv_layers.new()
  for loop in mesh.loops:layer.data[loop.index].uv=(uv[loop.vertex_index,0],1-uv[loop.vertex_index,1])
  for poly in mesh.polygons:poly.use_smooth=True
  normal=np.stack([n[:,0],-n[:,2],n[:,1]],1);mesh.normals_split_custom_set([normal[l.vertex_index] for l in mesh.loops])
  obj=bpy.data.objects.new(name+'_'+label,mesh);bpy.context.collection.objects.link(obj);result.append(obj)
 return result
names=['rabbit','dolphinchibi','rhino','orca','penguin']
if '--icons' in args:
 for name in names[:4]:
  bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);build(name)
  scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False;scene.world.color=(.6,.6,.6);scene.view_settings.view_transform='Standard';scene.render.film_transparent=True;scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.resolution_percentage=100
  for loc,energy in [((-.8,-1.8,2),35),((1,-.8,1),20)]:
   bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.size=1.5;o.rotation_euler=(Vector((0,0,.35))-o.location).to_track_quat('-Z','Y').to_euler()
  bpy.ops.object.camera_add(location=(0,-2,.39));o=bpy.context.object;o.data.type='ORTHO';o.data.ortho_scale=.9;o.rotation_euler=(Vector((0,0,.39))-o.location).to_track_quat('-Z','Y').to_euler();scene.camera=o
  scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA';scene.render.filepath=os.path.join(models,'..','Illustrations',('rabbitchibi' if name=='rabbit' else name)+'.png');bpy.ops.render.render(write_still=True)
 sys.exit(0)
if '--export' in args:
 for name in names[:4]:
  bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);objects=build(name)
  for obj in objects:
   obj.select_set(True)
   if '_eye' in obj.name:
    points=np.array([v.co[:] for v in obj.data.vertices]);center=(points.min(0)+points.max(0))/2
    for v in obj.data.vertices:v.co-=Vector(center)
    obj.location=center
  bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out,name+'.blend'));bpy.ops.export_scene.gltf(filepath=os.path.join(out,name+'.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for row,name in enumerate(names):
 for col,(blink,pose) in enumerate([(0,False),(.6,False),(1,False),(0,True)]):
  for obj in build(name,blink,pose):obj.location=(col*.85,0,(4-row)*.88)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=False;scene.world.color=(.5,.5,.5);scene.view_settings.view_transform='Standard';scene.render.resolution_x=1600;scene.render.resolution_y=1900;scene.render.resolution_percentage=100
for loc,energy in [((-2,-4,7),220),((5,-3,5),130)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.size=5;o.rotation_euler=(Vector((1.2,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(1.275,-8,2.2));o=bpy.context.object;o.data.type='ORTHO';o.data.ortho_scale=4.5;o.rotation_euler=(Vector((1.275,0,2.2))-o.location).to_track_quat('-Z','Y').to_euler();scene.camera=o;scene.render.filepath=os.path.join(out,'existing-blink-comparison.png');bpy.ops.render.render(write_still=True)
