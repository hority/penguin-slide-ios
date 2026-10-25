"""Extract runtime maps from four original GLBs: python ci/extract-tripo-textures.py MASTERS MODELS."""
import json,struct,io,sys
from PIL import Image
from pathlib import Path
for name in ['rabbit','dolphinchibi','rhino','orca']:
 d=(Path(sys.argv[1])/(name+'.glb')).read_bytes();n=struct.unpack_from('<I',d,12)[0];g=json.loads(d[20:20+n]);b=d[28+n:];m=g['materials'][0];pbr=m['pbrMetallicRoughness']
 for suffix,tx,size in [('base.jpg',pbr['baseColorTexture'],1024),('normal.png',m['normalTexture'],512),('rough.png',pbr['metallicRoughnessTexture'],512)]:
  im=g['images'][g['textures'][tx['index']]['source']];v=g['bufferViews'][im['bufferView']];a=Image.open(io.BytesIO(b[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])).convert('RGB')
  if suffix=='rough.png':a=a.getchannel('G').convert('RGB')
  a=a.resize((size,size),Image.Resampling.LANCZOS)
  if suffix=='rough.png':a=a.point(lambda v:max(v,90));a.save(str(Path(sys.argv[2])/(name+'_'+suffix)),quality=90)
