"""Convert a simplified, textured Tripo GLB to editable Blender/GLB and STG2 assets.
Run: blender -b --python ci/prepare-tripo-character.py -- NAME INPUT OUTPUT MODELS
Coordinates: glTF Y-up/+Z front; Blender Z-up/-Y front. No external skeleton required.
"""
import bpy, numpy as np, json, struct, sys, os, math
from mathutils import Vector
args = sys.argv[sys.argv.index('--')+1:]
name, source, output, models = args[:4]
os.makedirs(output, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source)
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
for o in objects:
 bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 # Tripo exports these four animals facing +X; rotate to Blender -Y (game +Z).
 o.rotation_mode="XYZ";o.rotation_euler.z=-math.pi/2;bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
for o in objects:
 bpy.context.view_layer.objects.active=o
 triangles=sum(len(p.vertices)-2 for p in o.data.polygons)
 if triangles>8800:
  mod=o.modifiers.new('Runtime triangle budget','DECIMATE');mod.ratio=8500/triangles;mod.use_collapse_triangulate=True
  bpy.ops.object.modifier_apply(modifier=mod.name)
points=np.concatenate([np.array([v.co[:] for v in o.data.vertices]) for o in objects])
lo,hi=points.min(0),points.max(0); height=.78 if name=='rabbit' else .70
scale=height/(hi[2]-lo[2]); offset=np.array([(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]])
for o in objects:
 for v in o.data.vertices: v.co=(np.array(v.co)-offset)*scale
 for p in o.data.polygons:p.use_smooth=True
 o.data.normals_split_custom_set([n.vector.normalized() for n in o.data.corner_normals])
 for loop in o.data.uv_layers.active.data: loop.uv=(max(0,min(1,loop.uv.x)),max(0,min(1,loop.uv.y)))
 # Use the exact small texture set bundled in the game for exports and previews.
 mat=bpy.data.materials.new(name+'_PBR');mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;bsdf=nodes.get('Principled BSDF')
 for suffix,socket in [('base.jpg','Base Color'),('rough.png','Roughness'),('normal.png','Normal')]:
  image=bpy.data.images.load(os.path.join(models,name+'_'+suffix));image.pack();tex=nodes.new('ShaderNodeTexImage');tex.image=image
  if suffix!='base.jpg':image.colorspace_settings.name='Non-Color'
  if socket=='Normal':
   normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.35;links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
  else:links.new(tex.outputs['Color'],bsdf.inputs[socket])
 o.data.materials.clear();o.data.materials.append(mat)
 for p in o.data.polygons:p.material_index=0
# Runtime vertex format: position, normal, vertically flipped UV; shader supplies rig weights.
vertices=[];indices=[];count=0
for o in objects:
 mesh=o.data;mesh.calc_loop_triangles(); uv=mesh.uv_layers.active.data
 rows=[]
 for tri in mesh.loop_triangles:
  for j in tri.loops:
   p=mesh.vertices[mesh.loops[j].vertex_index].co;n=mesh.corner_normals[j].vector.normalized();t=uv[j].uv
   rows.append((p.x,p.z,-p.y,n.x,n.z,-n.y,t.x,1-t.y))
 v,ix=np.unique(np.array(rows,dtype='<f4').round(6),axis=0,return_inverse=True)
 vertices.append(v);indices.append(ix+count);count+=len(v)
v=np.concatenate(vertices).astype('<f4');ix=np.concatenate(indices).astype('<u4')
with open(os.path.join(models,name.capitalize()+'.bin'),'wb') as f:
 header=b'{}';f.write(b'STG2'+struct.pack('<I',len(header))+header+struct.pack('<I',1));f.write(struct.pack('<H',4)+b'body'+struct.pack('<II',len(v),len(ix)));f.write(v[:,:3].tobytes()+v[:,3:6].tobytes()+v[:,6:8].tobytes()+ix.tobytes())
# Export a portable model and an editable master with all maps packed.
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(output,name+'.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output,name+'.blend'))
report={'name':name,'triangles':len(ix)//3,'vertices':len(v),'bounds':[v[:,:3].min(0).tolist(),v[:,:3].max(0).tolist()],'source':os.path.basename(source)}
open(os.path.join(output,name+'-metrics.json'),'w').write(json.dumps(report,indent=2));print(report)
if '--no-render' in args: sys.exit(0)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False
scene.world.color=(.65,.65,.65);scene.render.resolution_x=600;scene.render.resolution_y=700;scene.render.resolution_percentage=100;scene.render.film_transparent=True
scene.view_settings.view_transform='Standard'
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
for location,power,size in [((-.8,-1.8,2),35,1.5),((1,-.8,1),20,1.2),((0,1,1.3),30,1)]:
 bpy.ops.object.light_add(type='AREA',location=location);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,.35))
bpy.ops.object.camera_add(location=(0,-2,.43));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=.94;aim(camera,(0,0,.39));scene.camera=camera
scene.render.image_settings.file_format='PNG';scene.render.filepath=os.path.join(output,name+'-front.png');bpy.ops.render.render(write_still=True)
camera.location=(1,-1.7,.8);aim(camera,(0,0,.36));scene.render.filepath=os.path.join(output,name+'-three-quarter.png');bpy.ops.render.render(write_still=True)
