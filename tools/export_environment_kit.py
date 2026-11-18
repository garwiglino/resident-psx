"""Export only the supplied architecture; the Blender source is never saved."""
import bpy,pathlib,json,math,hashlib
import numpy as np
from mathutils import Matrix,Vector
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'assets'/'environment';out.mkdir(parents=True,exist_ok=True)
scene=bpy.context.scene
if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
source_path=pathlib.Path(bpy.data.filepath)
parts=[('Plane','wall_straight',Matrix.Rotation(math.pi/2,4,'Z') @ Matrix.Translation((-1,0,0))),
       ('Plane.001','floor_tile',Matrix.Identity(4)),
       ('Plane.012','ceiling_tile',Matrix.Translation((0,0,-3))),
       ('Plane.013','corner_inner',Matrix.Translation((-2,3,0))),
       ('Plane.014','corner_outer',Matrix.Translation((-2,6,0))),
       ('wall_door_frame','wall_door_frame',Matrix.Rotation(math.pi/2,4,'Z') @ Matrix.Translation((-1,-4,0))),
       ('door_01','door',Matrix.Rotation(math.pi/2,4,'Z') @ Matrix.Translation((-1,-4,0)))]
objects=[];report={'source':str(source_path),'source_sha256':hashlib.sha256(source_path.read_bytes()).hexdigest(),'parts':{}}
C=Matrix.Rotation(-math.pi/2,4,'X')
for source_name,name,normalization in parts:
    source=bpy.data.objects[source_name]
    original=source.data.copy();original.transform(normalization @ source.matrix_world);original.update()
    source.name='source_'+source_name
    ob=bpy.data.objects.new(name,original);scene.collection.objects.link(ob);objects.append(ob)
    points=[C @ v.co for v in original.vertices]
    uv=original.uv_layers.active.data if original.uv_layers.active else []
    faces=[]
    normal_areas={}
    for p in original.polygons:
        normal=C.to_3x3() @ p.normal
        key=','.join(str(round(v,1)) for v in normal)
        normal_areas[key]=normal_areas.get(key,0)+p.area
        if p.area<.5:continue
        faces.append({'normal':list((C.to_3x3() @ p.normal).normalized()),'center':list(C @ p.center),'area':p.area})
    report['parts'][name]={'vertices':len(original.vertices),'triangles':sum(len(p.vertices)-2 for p in original.polygons),
        'minimum':[min(v[i] for v in points) for i in range(3)],'maximum':[max(v[i] for v in points) for i in range(3)],
        'uv_min':[min(l.uv[i] for l in uv) for i in range(2)] if uv else [],'uv_max':[max(l.uv[i] for l in uv) for i in range(2)] if uv else [],'large_faces':faces,'normal_areas':normal_areas}

# A PSX page limits the addressable region, not the resolution of a whole atlas.
# Every supplied face already fits in one page: crop its used region at 1:1
# texel scale and remap UVs, without changing topology or repeating the motif.
image=bpy.data.images['download (54).png']
width,height=image.size
pixels=np.empty(width*height*4,dtype=np.float32)
image.pixels.foreach_get(pixels)
pixels=pixels.reshape(height,width,4)
face_bounds={};regions=set()
def contains(rect,bounds):
    x,y,w,h=rect
    return bounds[0]>=x-1e-4 and bounds[1]>=y-1e-4 and bounds[2]<=x+w+1e-4 and bounds[3]<=y+h+1e-4
def page_size(span):
    return 1 << max(0,math.ceil(math.log2(max(1,span-1e-4))))
for ob in objects:
    uv=ob.data.uv_layers.active.data
    for face in ob.data.polygons:
        coords=[uv[i].uv for i in face.loop_indices]
        bounds=(min(v.x for v in coords)*width,min(v.y for v in coords)*height,
                max(v.x for v in coords)*width,max(v.y for v in coords)*height)
        x=math.floor((bounds[0]+1e-4)/64)*64
        y=math.floor((bounds[1]+1e-4)/64)*64
        rect=(x,y,page_size(bounds[2]-x),page_size(bounds[3]-y))
        assert max(rect[2:])<=256,(ob.name,face.index,bounds,rect)
        regions.add(rect);face_bounds[(ob.name,face.index)]=bounds
# Share pages across all seven modules, including faces inside a larger crop.
regions=sorted(regions,key=lambda r:(-r[2]*r[3],r))
pages=[]
for rect in regions:
    bounds=(rect[0],rect[1],rect[0]+rect[2],rect[1]+rect[3])
    if not any(contains(existing,bounds) for existing in pages):pages.append(rect)
report['texture_pages']=[]
materials=[]
def save_crop(name,rect):
    x,y,w,h=rect
    crop=pixels[np.ix_((np.arange(y,y+h)%height),(np.arange(x,x+w)%width))].copy()
    page=bpy.data.images.new(name,width=w,height=h,alpha=True)
    page.colorspace_settings.name=image.colorspace_settings.name
    page.pixels.foreach_set(crop.ravel());page.update()
    page.filepath_raw=str(out/(name+'.png'));page.file_format='PNG';page.save()
    return page
for index,rect in enumerate(pages):
    name=f'surfaces_page_{index:02d}'
    page=save_crop(name,rect)
    mat=bpy.data.materials.new(name);mat.use_nodes=True
    shader=mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value=1.0
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=page;tex.interpolation='Closest'
    mat.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    materials.append(mat)
    report['texture_pages'].append({'file':name+'.png','atlas_rect_bottom_left':rect,'texel_scale':1})
for ob in objects:
    ob.data.materials.clear()
    for mat in materials:ob.data.materials.append(mat)
    uv=ob.data.uv_layers.active.data
    for face in ob.data.polygons:
        bounds=face_bounds[(ob.name,face.index)]
        index=min((i for i,r in enumerate(pages) if contains(r,bounds)),key=lambda i:pages[i][2]*pages[i][3])
        x,y,w,h=pages[index]
        face.material_index=index
        for loop_index in face.loop_indices:
            u,v=uv[loop_index].uv
            uv[loop_index].uv=((u*width-x)/w,(v*height-y)/h)
save_crop('surfaces_panel',(384,512,128,128))
report['texture_pages'].append({'file':'surfaces_panel.png','atlas_rect_bottom_left':[384,512,128,128],'texel_scale':1})
bpy.ops.object.select_all(action='DESELECT')
for ob in objects:ob.select_set(True);ob.hide_set(False);ob.hide_viewport=False
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(out/'scene_kit.glb'),export_format='GLB',use_selection=True,
    export_animations=False,export_apply=True,export_yup=True,export_cameras=False,export_lights=False)
if image:
    image.filepath_raw=str(out/'surfaces.png');image.file_format='PNG';image.save()
(out/'scene_kit.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('ENVIRONMENT_KIT_OK',json.dumps({k:{f:v for f,v in r.items() if f!='large_faces'} for k,r in report['parts'].items()}))
print('ENVIRONMENT_TEXTURE_PAGES_OK',json.dumps(report['texture_pages']))
