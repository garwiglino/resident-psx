"""Retain the painted garment mask when Blender merged its material slots."""
import json
from mathutils import Vector, geometry, kdtree

def recover_mask(mesh, transform, reference_path):
    source=json.loads(reference_path.read_text(encoding='utf8'))
    positions=[];lookup={};triangles=[];seen=set()
    for row in source['triangles']:
        ids=[]
        for point in row:
            key=tuple(point)
            if key not in lookup:lookup[key]=len(positions);positions.append(Vector(point))
            ids.append(lookup[key])
        key=frozenset(ids)
        if key in seen:continue
        seen.add(key)
        a,b,c=[positions[i] for i in ids]
        triangles.append((key,(b-a).cross(c-a).length*.5))
    tree=kdtree.KDTree(len(positions))
    for index,point in enumerate(positions):tree.insert(point,index)
    tree.balance()
    points=[transform @ vertex.co for vertex in mesh.data.vertices]
    mapped=[]
    for point in points:
        _,index,distance=tree.find(point);mapped.append(index if distance<.00002 else -1)
    result=[]
    for polygon in mesh.data.polygons:
        ids={mapped[index] for index in polygon.vertices}
        if -1 in ids or len(ids)<3:continue
        matching=[(triangle,area) for triangle,area in triangles if triangle<=ids]
        covered=sum(area for triangle,area in matching)
        face=[points[index] for index in polygon.vertices]
        area=0.0
        for triangle in geometry.tessellate_polygon([face]):
            a,b,c=[face[index] if isinstance(index,int) else index for index in triangle]
            area+=(b-a).cross(c-a).length*.5
        # A non-planar quad can use the opposite diagonal after a mesh repair.
        # Its original triangles still cover exactly the same polygon corners.
        exact_cover=len(matching)==len(ids)-2 and set().union(*(triangle for triangle,_ in matching))==ids
        if exact_cover or (covered>0 and abs(covered-area)<=max(1e-8,area*.0001)):result.append(polygon.index)
    assert result,'Shared body/mask material has no matching saved mask. Assign a separate coat mask material.'
    return result
