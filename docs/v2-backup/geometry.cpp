#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <vector>
#include <cmath>
#include <array>
using namespace godot;

class PSXGeometry : public RefCounted {
    GDCLASS(PSXGeometry,RefCounted)
    struct Entry {
        uint64_t id=0, skeleton_id=0;
        PackedVector3Array vertices,normals,static_positions,static_normals,static_light;
        PackedVector2Array uvs;
        PackedInt32Array indices,bones,bind_indices;
        PackedFloat32Array weights;
        std::vector<Transform3D> binds;
        Color tint,emission;
        Ref<Texture2D> texture;
        AABB aabb;
        bool fixed=false;
    };
    struct Vertex {Vector3 p; Color c; Vector2 uv;};
    struct Primitive {std::array<Vector2,3> points,uvs; std::array<Color,3> colors; Ref<Texture2D> texture; int bucket,order;};
    std::vector<Entry> entries;
    std::vector<Primitive> triangles;
    Transform3D inverse;
    Basis rotation;
    Vector3 camera_position,torch_direction;
    bool torch=true,power=false,snap=true;
    double focal=444.444;
    int vertices_processed=0;
    int batch_count=0;
    double far_clip=42.0,near_clip=.1,fog_start=9.0,fog_end=33.0;
    int ordering_buckets=1024;
    static double clamp(double x,double a,double b){return std::max(a,std::min(b,x));}
    static Vector3 quantize(Vector3 p,double units,bool round_value=true){
        for(int i=0;i<3;i++)p[i]=(round_value?std::round(p[i]*units):std::floor(p[i]*units))/units;
        return p;
    }
    Vector3 bake(Vector3 p,Vector3 n,Color tint,Color emission){
        const Vector3 lamps[5]={{-2.8,2.8,5},{2.7,2.8,-3},{-2.8,2.8,-11},{2.7,2.8,-20},{0,2.7,-28}};
        const Vector3 colors[5]={{1.05,.71,.4},{.4,.85,.79},{.94,.32,.21},{.60,.83,.72},{.9,.12,.06}};
        Vector3 light=Vector3(.19,.22,.24)+Vector3(.09,.1,.11)*std::max(double(n.y),0.0);
        for(int i=0;i<5;i++){
            Vector3 d=lamps[i]-p; double distance=d.length();
            double a=std::max(1-distance/8,0.0);
            Vector3 c=(i==4&&power)?Vector3(.45,.9,.63):colors[i];
            if(a>0)light+=c*std::max(double(n.dot(d/std::max(distance,.001))),0.0)*a*a;
        }
        return Vector3(tint.r,tint.g,tint.b)*light+Vector3(emission.r,emission.g,emission.b);
    }
    Color shade(Vector3 p,Vector3 n,double depth,Color tint,Vector3 rgb){
        if(torch){
            Vector3 d=p-camera_position; double distance=d.length();
            Vector3 direction=d/std::max(distance,.001);
            double cone=clamp((direction.dot(torch_direction)-.78)/.16,0,1);
            cone=cone*cone*(3-2*cone);
            double a=std::max(1-distance/16,0.0);
            rgb+=Vector3(tint.r,tint.g,tint.b)*Vector3(1,.93,.77)*cone*a*std::max(double(n.dot(-direction)),.12)*2;
        }
        double fog=clamp((depth-fog_start)/std::max(fog_end-fog_start,.001),0,.88);
        rgb=rgb.lerp(Vector3(.027,.044,.046),fog);
        for(int i=0;i<3;i++)rgb[i]=clamp(std::floor(rgb[i]*128),0,255)/128;
        return Color(rgb.x,rgb.y,rgb.z,1);
    }
    void submit(const Vertex &a,const Vertex &b,const Vertex &c,const Ref<Texture2D> &texture){
        const Vertex v[3]={a,b,c}; Vector2 p[3]; double z=0;
        for(int i=0;i<3;i++){
            p[i]=Vector2(160+v[i].p.x*focal/-v[i].p.z,120-v[i].p.y*focal/-v[i].p.z);
            if(snap){p[i].x=std::floor(p[i].x);p[i].y=std::floor(p[i].y);}
            z-=v[i].p.z/3;
        }
        if((p[1]-p[0]).cross(p[2]-p[0])<=0)return;
        if((p[0].x<0&&p[1].x<0&&p[2].x<0)||(p[0].x>320&&p[1].x>320&&p[2].x>320)||
           (p[0].y<0&&p[1].y<0&&p[2].y<0)||(p[0].y>240&&p[1].y>240&&p[2].y>240))return;
        Primitive out; out.texture=texture;out.bucket=int(clamp(z/far_clip*(ordering_buckets-1),0,ordering_buckets-1));out.order=int(triangles.size());
        for(int i=0;i<3;i++){out.points[i]=p[i];out.colors[i]=v[i].c;out.uvs[i]=v[i].uv;}
        triangles.push_back(out);
    }
    void triangle(Vertex a,Vertex b,Vertex c,const Ref<Texture2D> &texture){
        if(a.p.z<-near_clip&&b.p.z<-near_clip&&c.p.z<-near_clip){submit(a,b,c,texture);return;}
        if(a.p.z>=-near_clip&&b.p.z>=-near_clip&&c.p.z>=-near_clip)return;
        Vertex input[3]={a,b,c};std::vector<Vertex> clipped;Vertex previous=c;
        for(auto current:input){
            bool inside=current.p.z<-near_clip,old_inside=previous.p.z<-near_clip;
            if(inside!=old_inside){
                double t=(-near_clip-previous.p.z)/(current.p.z-previous.p.z);
                clipped.push_back({previous.p.lerp(current.p,t),previous.c.lerp(current.c,t),previous.uv.lerp(current.uv,t)});
            }
            if(inside)clipped.push_back(current);
            previous=current;
        }
        for(size_t j=1;j+1<clipped.size();j++)submit(clipped[0],clipped[j],clipped[j+1],texture);
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("configure","entries"),&PSXGeometry::configure);
        ClassDB::bind_method(D_METHOD("frame","camera","fov","torch","power","snap"),&PSXGeometry::frame);
        ClassDB::bind_method(D_METHOD("get_statistics"),&PSXGeometry::get_statistics);
        ClassDB::bind_method(D_METHOD("set_render_settings","settings"),&PSXGeometry::set_render_settings);
    }
public:
    void set_render_settings(Dictionary settings){
        far_clip=std::max(double(settings.get("far_clip",42.0)),1.0);
        near_clip=std::max(double(settings.get("near_clip",.1)),.001);
        fog_start=double(settings.get("fog_start",9.0));fog_end=double(settings.get("fog_end",33.0));
        ordering_buckets=std::max(int(settings.get("ordering_buckets",1024)),16);
    }
    Dictionary get_statistics()const{
        Dictionary d;d["triangles"]=int(triangles.size());d["vertices"]=vertices_processed;d["batches"]=batch_count;return d;
    }
    void configure(Array input){
        entries.clear();
        for(int i=0;i<input.size();i++){
            Dictionary d=input[i];Entry e;
            Object *node=d["node"];e.id=node->get_instance_id();
            Object *skeleton=d["skeleton"];if(skeleton)e.skeleton_id=skeleton->get_instance_id();
            e.vertices=d["vertices"];if(d["normals"].get_type()!=Variant::NIL)e.normals=d["normals"];
            if(d["uvs"].get_type()!=Variant::NIL)e.uvs=d["uvs"];
            e.indices=d["indices"];e.bind_indices=d["bind_indices"];
            if(e.skeleton_id){e.bones=d["bones"];e.weights=d["weights"];}
            Array binds=d["binds"];for(int b=0;b<binds.size();b++)e.binds.push_back(binds[b]);
            e.tint=d["color"];e.emission=d["emission"];e.texture=d["texture"];e.aabb=d["aabb"];e.fixed=d["fixed"];
            e.static_positions=d["static_positions"];e.static_normals=d["static_normals"];e.static_light=d["static_light"];
            entries.push_back(e);
        }
    }
    Array frame(Transform3D camera,double fov,bool torch_enabled,bool power_enabled,bool snap_enabled){
        bool changed=power!=power_enabled; power=power_enabled;torch=torch_enabled;snap=snap_enabled;
        inverse=camera.affine_inverse();rotation=inverse.basis;
        for(int i=0;i<3;i++)rotation.set_column(i,quantize(rotation.get_column(i),4096));
        focal=120/std::tan(fov*3.141592653589793/360);
        camera_position=camera.origin;torch_direction=-camera.basis.get_column(2);
        triangles.clear();vertices_processed=0;
        for(auto &e:entries){
            auto node=Object::cast_to<MeshInstance3D>(UtilityFunctions::instance_from_id(e.id));
            if(!node||!node->is_visible_in_tree())continue;
            Transform3D transform=node->get_global_transform();
            if(e.fixed){
                Vector3 center=inverse.xform(transform.xform(e.aabb.get_center()));
                double radius=e.aabb.size.length()*.5;
                double depth=-center.z;
                if(depth+radius<near_clip||depth-radius>far_clip||std::abs(center.x)>depth*160/focal+radius||std::abs(center.y)>depth*120/focal+radius)continue;
            }
            auto skeleton=e.skeleton_id?Object::cast_to<Skeleton3D>(UtilityFunctions::instance_from_id(e.skeleton_id)):nullptr;
            std::vector<Transform3D> skin;
            if(skeleton)for(size_t i=0;i<e.binds.size();i++)skin.push_back(skeleton->get_global_transform()*skeleton->get_bone_global_pose(e.bind_indices[i])*e.binds[i]);
            Basis normal_matrix=transform.basis.inverse().transposed();
            std::vector<Vertex> vertices(e.vertices.size());
            Vector2 texture_size(e.texture->get_width(),e.texture->get_height());
            for(int i=0;i<e.vertices.size();i++){
                Vector3 p=e.vertices[i],n=e.normals.size()?e.normals[i]:Vector3(0,1,0),world_pos,world_normal;
                if(e.fixed){world_pos=e.static_positions[i];world_normal=e.static_normals[i];}
                else if(skeleton){
                    for(int w=0;w<4;w++){
                        int bone=e.bones[i*4+w];double weight=e.weights[i*4+w];
                        if(weight>0&&bone<int(skin.size())){world_pos+=skin[bone].xform(p)*weight;world_normal+=skin[bone].basis.xform(n)*weight;}
                    }
                }else{world_pos=transform.xform(p);world_normal=normal_matrix.xform(n);}
                world_pos=quantize(world_pos,1024);world_normal.normalize();
                Vector3 view=quantize(rotation.xform(world_pos-camera_position),1024,false);
                Vector3 base;
                if(e.fixed){
                    if(changed)e.static_light.set(i,bake(world_pos,world_normal,e.tint,e.emission));
                    base=e.static_light[i];
                }else base=bake(world_pos,world_normal,e.tint,e.emission);
                Color color=shade(world_pos,world_normal,-view.z,e.tint,base);
                Vector2 uv=e.uvs.size()?e.uvs[i]:Vector2();
                uv.x=std::floor(uv.x*texture_size.x)/texture_size.x;
                uv.y=std::floor(uv.y*texture_size.y)/texture_size.y;
                vertices[i]={view,color,uv};
            }
            vertices_processed+=int(vertices.size());
            for(int i=0;i+2<e.indices.size();i+=3)triangle(vertices[e.indices[i]],vertices[e.indices[i+1]],vertices[e.indices[i+2]],e.texture);
        }
        std::sort(triangles.begin(),triangles.end(),[](const Primitive &a,const Primitive &b){return a.bucket!=b.bucket?a.bucket>b.bucket:a.order>b.order;});
        // Merge only ADJACENT texture runs after sorting: painter order is unchanged.
        Array output;
        for(size_t first=0;first<triangles.size();){
            size_t last=first+1;
            while(last<triangles.size()&&triangles[last].texture==triangles[first].texture)last++;
            int count=int(last-first)*3;
            PackedVector2Array points,uvs;PackedColorArray colors;PackedInt32Array indices;
            points.resize(count);uvs.resize(count);colors.resize(count);indices.resize(count);
            auto pp=points.ptrw();auto pu=uvs.ptrw();auto pc=colors.ptrw();auto pi=indices.ptrw();
            for(size_t i=first;i<last;i++)for(int j=0;j<3;j++){
                int at=int(i-first)*3+j;pp[at]=triangles[i].points[j];pu[at]=triangles[i].uvs[j];pc[at]=triangles[i].colors[j];pi[at]=at;
            }
            Dictionary d;d["points"]=points;d["uvs"]=uvs;d["colors"]=colors;d["indices"]=indices;d["texture"]=triangles[first].texture;
            output.append(d);first=last;
        }
        batch_count=output.size();
        return output;
    }
};

void initialize_psx(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE)ClassDB::register_class<PSXGeometry>();}
void uninitialize_psx(ModuleInitializationLevel level){}
extern "C" GDExtensionBool GDE_EXPORT psx_library_init(GDExtensionInterfaceGetProcAddress get_proc,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){
    GDExtensionBinding::InitObject init(get_proc,library,initialization);
    init.register_initializer(initialize_psx);init.register_terminator(uninitialize_psx);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
