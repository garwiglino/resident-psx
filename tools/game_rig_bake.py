"""Bake Rigify B-Bones into ordinary weighted joints, preserving the deformation.
Control rigs and artist files are untouched; all generated objects are export-only.
"""
import bpy,math
from mathutils import Matrix,Vector

class GameRigBake:
    def __init__(self,rig,meshes,frame):
        self.source=rig;self.meshes=meshes;self.samples=[];self.segments={};self.weights={};self.mesh_matrices={};self.vertex_bones={}
        bpy.context.scene.frame_set(frame)
        ev=rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        self.rest={b.name:b.matrix_local.copy() for b in rig.data.bones if b.use_deform}
        self.lengths={b.name:b.length for b in rig.data.bones if b.use_deform}
        self.world=rig.matrix_world.copy()
        self.first_root=ev.pose.bones['root'].matrix.translation.copy() if 'root' in ev.pose.bones else Vector()
        self.first_yaw=ev.pose.bones['root'].matrix.to_euler('XYZ').z if 'root' in ev.pose.bones else 0
        self.dropped_weight=0
        for mesh in meshes:
            transform=rig.matrix_world.inverted_safe() @ mesh.matrix_world
            self.mesh_matrices[mesh.name]=transform
            vertex_weights=[]
            for v in mesh.data.vertices:
                point=transform @ v.co;weights={}
                for g in v.groups:
                    name=mesh.vertex_groups[g.group].name
                    if name not in self.rest or g.weight<=.000001:continue
                    bone=ev.pose.bones[name]
                    if bone.bone.bbone_segments>1:
                        index,blend=bone.bbone_segment_index(point)
                        for segment,factor in [(index,1-blend),(index+1,blend)]:
                            if g.weight*factor<=.000001:continue
                            target='SEG-'+name+'-%02d'%segment
                            weights[target]=weights.get(target,0)+g.weight*factor
                            if target not in self.segments:
                                self.segments[target]=(name,segment,bone.bone.matrix_local @ bone.bbone_segment_matrix(segment,rest=True))
                    else:weights[name]=weights.get(name,0)+g.weight
                ranked=sorted(weights.items(),key=lambda item:item[1],reverse=True)
                # Rare vertices exceed glTF/Godot's eight influences after splitting B-Bones.
                # Bake their blended position to one joint instead of discarding weights.
                if len(ranked)>8:
                    total=sum(w for n,w in ranked)
                    target='VTX-'+mesh.name+'-%04d'%v.index
                    self.vertex_bones[target]=(point.copy(),[(n,w/total) for n,w in ranked])
                    ranked=[(target,1.0)]
                total=sum(w for n,w in ranked)
                vertex_weights.append([(n,w/total) for n,w in ranked])
            self.weights[mesh.name]=vertex_weights

    def sample(self,frame,dep):
        ev=self.source.evaluated_get(dep)
        root=ev.pose.bones.get('root')
        delta=Matrix.Identity(4)
        if root:
            d=root.matrix.translation-self.first_root
            delta=Matrix.Translation(Vector((d.x,d.y,0))) @ Matrix.Rotation(root.matrix.to_euler('XYZ').z-self.first_yaw,4,'Z')
        poses={name:ev.pose.bones[name].matrix.copy() for name in self.rest}
        for target,(name,index,rest) in self.segments.items():
            poses[target]=ev.pose.bones[name].matrix @ ev.pose.bones[name].bbone_segment_matrix(index,rest=False)
        for target,(point,weights) in self.vertex_bones.items():
            skin=Matrix(((0,0,0,0),)*4)
            for name,weight in weights:
                rest=self.segments[name][2] if name in self.segments else self.rest[name]
                skin+=(poses[name] @ rest.inverted())*weight
            location,rotation,scale=skin.decompose()
            pose=rotation.to_matrix().to_4x4() @ Matrix.Diagonal((*scale,1))
            pose.translation=skin @ point
            poses[target]=pose
        self.samples.append((frame,delta,poses))

    def build(self,clip):
        if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
        self.source.name='Rigify_source'
        data=bpy.data.armatures.new('GameRigData');rig=bpy.data.objects.new('rig',data)
        bpy.context.scene.collection.objects.link(rig);rig.matrix_world=self.world
        bpy.context.view_layer.objects.active=rig;rig.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        root=data.edit_bones.new('RootMotion');root.head=(0,0,0);root.tail=(0,.1,0);root.use_deform=True
        for name,rest in self.rest.items():
            b=data.edit_bones.new(name);b.head=(0,0,0);b.tail=(0,max(self.lengths[name],.01),0);b.matrix=rest;b.parent=root;b.use_deform=True
        for target,(name,index,rest) in sorted(self.segments.items()):
            b=data.edit_bones.new(target);b.head=(0,0,0);b.tail=(0,max(self.lengths[name]/10,.005),0);b.matrix=rest;b.parent=data.edit_bones[name];b.use_deform=True
        for target,(point,weights) in sorted(self.vertex_bones.items()):
            b=data.edit_bones.new(target);b.head=point;b.tail=point+Vector((0,.01,0));b.parent=root;b.use_deform=True
        bpy.ops.object.mode_set(mode='OBJECT')
        created=[]
        for source in self.meshes:
            source_name=source.name;source.name=source_name+'_source'
            mesh=source.data.copy();mesh.transform(self.mesh_matrices[source_name]);mesh.update()
            ob=bpy.data.objects.new(source_name,mesh);bpy.context.scene.collection.objects.link(ob)
            ob.parent=rig;ob.matrix_parent_inverse=Matrix.Identity(4);ob.matrix_basis=Matrix.Identity(4)
            # Recreate then clear the original group table to remove copied deform assignments.
            for group in source.vertex_groups:ob.vertex_groups.new(name=group.name)
            ob.vertex_groups.clear()
            groups={name:ob.vertex_groups.new(name=name) for name in sorted({n for row in self.weights[source_name] for n,w in row})}
            for index,row in enumerate(self.weights[source_name]):
                for name,weight in row:groups[name].add([index],weight,'REPLACE')
            mod=ob.modifiers.new('GameSkin','ARMATURE');mod.object=rig
            created.append(ob)
        for frame,delta,poses in self.samples:
            bpy.context.scene.frame_set(frame)
            targets={'RootMotion':delta,**poses}
            for bone in rig.pose.bones:
                parent_pose=targets[bone.parent.name] if bone.parent else None
                options=dict(parent_matrix=parent_pose,parent_matrix_local=bone.parent.bone.matrix_local) if bone.parent else {}
                basis=bone.bone.convert_local_to_pose(targets[bone.name],bone.bone.matrix_local,invert=True,**options)
                bone.rotation_mode='QUATERNION'
                bone.location,bone.rotation_quaternion,bone.scale=basis.decompose()
                for prop in ['location','rotation_quaternion','scale']:bone.keyframe_insert(prop,frame=frame)
        rig.animation_data.action.name=clip
        self.root_distance=(self.samples[-1][1].translation-self.samples[0][1].translation).length
        return rig,created
