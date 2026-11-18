#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <vector>
#include <cmath>
#include <array>
#include <numeric>
#include <unordered_map>
#include <unordered_set>
#include <chrono>
using namespace godot;

class PSXGeometry : public RefCounted {
    GDCLASS(PSXGeometry,RefCounted)
    struct Vertex {
        Vector3 p;
        Color c;
        Vector2 uv,reflection_uv;
        float reflection_amount=0;
        Vector3 cel_light;
    };
    struct Reflection {
        int page=0,projection=0;
        float strength=0,light_response=0,motion=0,width=1.15,scale=1,angle=0,scene=0;
        Vector2 offset,texture_size;
        AABB bounds;
        std::vector<Vector2> mesh_uvs;
    };
    struct Entry {
        uint64_t id=0,skeleton_id=0;
        std::vector<Vector3> vertices,normals,static_positions,static_normals,static_light;
        std::vector<Vector2> uvs;
        std::vector<int32_t> indices,bones,bind_indices;
        std::vector<float> weights;
        int influences=4;
        std::vector<Transform3D> binds,skin;
        std::vector<Vertex> projected;
        Transform3D fixed_transform;
        Vector3 center,local_center;
        double radius=0;
        Color tint,emission;
        bool fixed=false,textured=false,sprite=false,depth_correct=false,unlit=false,hover_unlit=false;
        bool light_occluder=false,light_receiver=false,occluder_visible=false,torch_receiver=true,ignore_self_shadow=false;
        bool anime_character=false,ink_frame_ready=false;
        std::vector<Vertex> ink_projected;
        Transform3D occluder_transform,receiver_transform;
        uint64_t visibility_revision=0;
        std::vector<uint8_t> light_visibility;
        uint64_t light_revision=0;
        int page=0,page_index=0,blend_mode=0,surface=0;
        int64_t unlit_light_id=0;
        int face_part=0;
        std::array<int,2> face_pages={0,0};
        Reflection reflection;
    };
    struct Primitive {
        std::array<Vector2,3> points,uvs,reflection_uvs;
        std::array<Color,3> colors;
        std::array<float,3> inverse_depths,depth_scores,reflection_amounts;
        std::array<Vector3,3> cel_lights;
        int next=-1,page_index=0,blend_mode=0,reflection_page=0,cel_mode=0;
        bool ink=false,silhouette=false,mirror=false;
    };
    struct AnimeSettings {
        bool enabled=false,other_characters=true,outline_enabled=true;
        double strength=1,world_strength=0,outline_width=.006;
        Vector3 outline_color=Vector3(.025,.02,.04);
    } anime;
    std::vector<Entry> entries;
    struct WorldLight { Vector3 position,color,direction=Vector3(0,0,-1); double energy=1,range=6,outer_cos=.9,inner_cos=.95; int type=0; int64_t id=0; };
    struct ReflectionLight {
        WorldLight source;
        Vector3 center;
        int palette_index=0,world_index=-1;
        double score=0;
        bool planar=false;
    };
    std::vector<WorldLight> world_lights;
    PackedVector3Array reflection_light_colors;
    std::unordered_map<int64_t,Vector3> fixture_emissions;
    Vector3 ambient_light;
    uint64_t lighting_revision=1;
    bool lighting_configured=false;
    struct Occluder { Vector3 a,b,c,low,high; std::array<Vector2,3> uv; int page=0; uint64_t id=0; };
    struct BVHNode { Vector3 low,high; int first=0,count=0,left=-1,right=-1; };
    std::vector<Occluder> occluders;
    std::vector<BVHNode> light_bvh;
    struct LightSampleCache {
        uint64_t revision=0;
        Transform3D transform;
        std::vector<float> weights;
        float *prepare(uint64_t next_revision,Transform3D next_transform,size_t count){
            if(revision!=next_revision||transform!=next_transform){
                revision=next_revision;
                transform=next_transform;
                weights.assign(count,-1);
            }
            return weights.data();
        }
    };
    std::vector<LightSampleCache> shot_samples;
    uint64_t shot_revision=1;
    bool occluders_dirty=true,light_occlusion=true,general_depth=true;
    uint64_t visibility_revision=1;
    mutable uint64_t shadow_rays=0,shadow_triangle_tests=0;
    std::vector<Primitive> triangles;
    int anime_triangles=0,outline_triangles=0;
    int64_t frame_us=0;
    int entry_cel_mode=0;
    bool entry_silhouette=false;
    std::vector<int> ordered_triangles;
    std::vector<int32_t> ordering_table;
    Ref<Texture2D> atlas;
    // Local visibility exception for the player and held weapon. The world still
    // uses the original bucket/LIFO painter order, including world/world overlap.
    PackedVector4Array atlas_pages;
    PackedByteArray atlas_rgba,visibility_bytes;
    int atlas_width=0,depth_triangles=0,depth_pixels=0;
    std::vector<bool> opaque_pages;
    std::array<uint8_t,320*240> player_coverage{};
    Ref<Image> visibility_image,mirror_visibility_image;
    Ref<ImageTexture> visibility_texture,mirror_visibility_texture;
    double affine_strength=1;
    Transform3D inverse;
    Basis rotation;
    Vector3 camera_position,torch_position,torch_direction=Vector3(0,0,-1),torch_color=Vector3(1,1,1);
    double torch_energy=2,torch_range=16,torch_outer_cos=std::cos(22.0*3.141592653589793/180),torch_inner_cos=std::cos(13.2*3.141592653589793/180);
    Vector3 shot_position,shot_color;
    double shot_energy=0,shot_range_squared=1;
    bool torch=true,power=false,snap=true;
    bool has_reflection_pages=false;
    bool capturing_mirror=false;
    Vector3 mirror_view_axis;
    Vector3 mirror_plane_center;
    double mirror_clip_offset=0;
    uint64_t mirror_node=0;
    int mirror_surface=-1;
    bool entry_mirror=false;
    double focal=444.444;
    int vertices_processed=0,batch_count=0;
    double far_clip=42,near_clip=.1,fog_start=9,fog_end=33;
    double orthographic_size=0;
    Vector3 fog_color=Vector3(.027,.044,.046);
    int ordering_buckets=1024;
    static double clamp(double x,double a,double b){return std::max(a,std::min(b,x));}
    template<class T,class Packed> static std::vector<T> copy(const Packed &array){
        if(!array.size())return {};
        return std::vector<T>(array.ptr(),array.ptr()+array.size());
    }
    static Vector3 quantize(Vector3 p,double units,bool rounded=true){
        for(int i=0;i<3;i++)p[i]=(rounded?std::round(p[i]*units):std::floor(p[i]*units))/units;
        return p;
    }
    static Vector3 low3(Vector3 a,Vector3 b){return Vector3(std::min(a.x,b.x),std::min(a.y,b.y),std::min(a.z,b.z));}
    static Vector3 high3(Vector3 a,Vector3 b){return Vector3(std::max(a.x,b.x),std::max(a.y,b.y),std::max(a.z,b.z));}
    bool opaque_uv(int page,Vector2 uv)const{
        if(page<=0||page>=atlas_pages.size()||opaque_pages[page]||atlas_rgba.is_empty())return true;
        const Vector4 &rect=atlas_pages[page];int w=int(rect.z),h=int(rect.w);
        if(w<=0||h<=0)return true;
        int x=int(std::floor(uv.x*w+.00001f))%w,y=int(std::floor(uv.y*h+.00001f))%h;
        if(x<0)x+=w;if(y<0)y+=h;
        size_t at=(size_t(int(rect.y)+y)*atlas_width+int(rect.x)+x)*4+3;
        return at<size_t(atlas_rgba.size())&&atlas_rgba[at]>=128;
    }
    int build_bvh(int first,int count){
        BVHNode node;node.low=Vector3(1e20,1e20,1e20);node.high=-node.low;
        for(int i=first;i<first+count;i++){node.low=low3(node.low,occluders[i].low);node.high=high3(node.high,occluders[i].high);}
        int index=int(light_bvh.size());light_bvh.push_back(node);
        if(count<=6){light_bvh[index].first=first;light_bvh[index].count=count;return index;}
        Vector3 size=node.high-node.low;int axis=size.max_axis_index(),middle=first+count/2;
        std::nth_element(occluders.begin()+first,occluders.begin()+middle,occluders.begin()+first+count,
            [axis](const Occluder &a,const Occluder &b){return a.low[axis]+a.high[axis]<b.low[axis]+b.high[axis];});
        int left=build_bvh(first,middle-first),right=build_bvh(middle,first+count-middle);
        light_bvh[index].left=left;light_bvh[index].right=right;return index;
    }
    void update_occluders(){
        bool dirty=occluders_dirty;
        for(auto &e:entries)if(e.light_occluder){
            auto node=Object::cast_to<MeshInstance3D>(UtilityFunctions::instance_from_id(e.id));
            bool visible=node&&node->is_visible_in_tree();Transform3D transform=visible?node->get_global_transform():Transform3D();
            if(visible!=e.occluder_visible||(visible&&transform!=e.occluder_transform))dirty=true;
            e.occluder_visible=visible;e.occluder_transform=transform;
        }
        if(!dirty)return;
        occluders_dirty=false;occluders.clear();light_bvh.clear();
        for(const auto &e:entries)if(e.light_occluder&&e.occluder_visible&&!e.skeleton_id){
            for(size_t i=0;i+2<e.indices.size();i+=3){
                int a=e.indices[i],b=e.indices[i+1],c=e.indices[i+2];Occluder t;
                t.a=e.occluder_transform.xform(e.vertices[a]);t.b=e.occluder_transform.xform(e.vertices[b]);t.c=e.occluder_transform.xform(e.vertices[c]);
                if((t.b-t.a).cross(t.c-t.a).length_squared()<1e-14)continue;
                t.low=low3(t.a,low3(t.b,t.c))-Vector3(.0001,.0001,.0001);t.high=high3(t.a,high3(t.b,t.c))+Vector3(.0001,.0001,.0001);
                t.page=e.page_index;t.id=e.id;t.uv={e.uvs[a],e.uvs[b],e.uvs[c]};occluders.push_back(t);
            }
        }
        if(!occluders.empty())build_bvh(0,int(occluders.size()));
        visibility_revision++;lighting_revision++;
    }
    static bool ray_box(const BVHNode &box,Vector3 origin,Vector3 direction,double distance){
        double near=0,far=distance;
        for(int i=0;i<3;i++){
            if(std::abs(direction[i])<1e-10){if(origin[i]<box.low[i]||origin[i]>box.high[i])return false;continue;}
            double a=(box.low[i]-origin[i])/direction[i],b=(box.high[i]-origin[i])/direction[i];if(a>b)std::swap(a,b);
            near=std::max(near,a);far=std::min(far,b);if(near>far)return false;
        }
        return true;
    }
    bool blocked(Vector3 point,Vector3 normal,Vector3 direction,double distance,uint64_t ignored_id=0)const{
        if(!light_occlusion||light_bvh.empty())return false;
        shadow_rays++;Vector3 origin=point+normal*.003+direction*.002;
        distance-=.004;if(distance<=0)return false;
        std::array<int,128> stack{};int size=1;stack[0]=0;
        while(size){const auto &node=light_bvh[stack[--size]];if(!ray_box(node,origin,direction,distance))continue;
            if(node.count){for(int i=node.first;i<node.first+node.count;i++){
                const auto &t=occluders[i];if(ignored_id&&t.id==ignored_id)continue;
                shadow_triangle_tests++;Vector3 e1=t.b-t.a,e2=t.c-t.a,p=direction.cross(e2);
                double det=e1.dot(p);if(std::abs(det)<1e-10)continue;double inv_det=1/det;
                Vector3 s=origin-t.a;double u=s.dot(p)*inv_det;if(u<-.000001||u>1.000001)continue;
                Vector3 q=s.cross(e1);double v=direction.dot(q)*inv_det;if(v<-.000001||u+v>1.000001)continue;
                double hit=e2.dot(q)*inv_det;if(hit<=.0005||hit>=distance)continue;
                if(opaque_uv(t.page,t.uv[0]*(1-u-v)+t.uv[1]*u+t.uv[2]*v))return true;
            }}else{stack[size++]=node.left;stack[size++]=node.right;}
        }
        return false;
    }
    double nearby_light_visibility(const Entry &e,Vector3 point,Vector3 query,Vector3 normal,
        Vector3 source,uint64_t ignored_id)const{
        Vector3 ray=source-query;
        double length=ray.length();
        Vector3 direction=ray/std::max(length,.001);
        bool center_blocked=blocked(query,normal,direction,length,ignored_id);
        if(!e.light_receiver)return center_blocked?0.0:1.0;

        // A modular surface shares vertices along its boundary. A second
        // nearby sample within the same room avoids full-black wedges when
        // the first ray just grazes a pillar, jamb or wall corner.
        Vector3 inset=query-point;
        double size=inset.length();
        if(size<=.001)return center_blocked?0.0:1.0;
        Vector3 alternative=query+inset*std::min(.08/size,1.0);
        Vector3 second_ray=source-alternative;
        double second_length=second_ray.length();
        bool second_blocked=blocked(alternative,normal,second_ray/std::max(second_length,.001),second_length,ignored_id);
        return (double(!center_blocked)+double(!second_blocked))*.5;
    }
    Vector3 bake(Vector3 p,Vector3 n,Color tint,Color emission,uint8_t *visibility=nullptr,const Vector3 *sample=nullptr,uint64_t ignored_id=0)const{
        Vector3 light=ambient_light;
        Vector3 query=sample?*sample:p;
        for(size_t index=0;index<world_lights.size();index++){const auto &source=world_lights[index];
            if(source.energy<=0)continue;
            if(source.type==2){
                double diffuse=std::max(double(n.dot(-source.direction)),0.0);if(diffuse<=0)continue;
                uint8_t seen=visibility?visibility[index]:255;
                if(seen==255){seen=blocked(query,n,-source.direction,100000,ignored_id)?0:1;if(visibility)visibility[index]=seen;}
                if(seen)light+=source.color*source.energy*diffuse;continue;
            }
            Vector3 d=source.position-p;double distance=d.length(),a=std::max(1-distance/source.range,0.0);
            if(a>0){
                Vector3 direction=d/std::max(distance,.001);double cone=1;
                if(source.type==1){cone=clamp((-direction.dot(source.direction)-source.outer_cos)/(source.inner_cos-source.outer_cos),0,1);cone=cone*cone*(3-2*cone);}
                double diffuse=std::max(double(n.dot(direction)),0.0);if(diffuse<=0||cone<=0)continue;
                uint8_t seen=visibility?visibility[index]:255;
                if(seen==255){Vector3 ray=source.position-query;double length=ray.length();seen=blocked(query,n,ray/std::max(length,.001),length,ignored_id)?0:1;if(visibility)visibility[index]=seen;}
                if(seen)light+=source.color*source.energy*diffuse*a*a*cone;
            }
        }
        return Vector3(tint.r,tint.g,tint.b)*light+Vector3(emission.r,emission.g,emission.b);
    }
    Color shade(Vector3 p,Vector3 n,const Entry &e,Vector3 rgb,Vector3 query,Vertex &vertex,
        float *shot_sample)const{
        float flags=float(e.page|(e.depth_correct?64:0))/255;
        uint64_t ignored_id=e.ignore_self_shadow?e.id:0;
        if(e.sprite)return Color(128.0f/255,128.0f/255,128.0f/255,flags);
        double torch_weight=0;
        if(torch&&e.torch_receiver&&!e.unlit&&!e.hover_unlit&&!e.unlit_light_id){
            Vector3 delta=p-torch_position;
            double square=delta.length_squared();
            if(square<torch_range*torch_range){
                double distance=std::sqrt(square);
                Vector3 direction=delta/std::max(distance,.001);
                double cone=clamp((direction.dot(torch_direction)-torch_outer_cos)/(torch_inner_cos-torch_outer_cos),0,1);
                if(cone>0){
                    cone=cone*cone*(3-2*cone);
                    Vector3 ray=torch_position-query;
                    double length=ray.length();
                    if(!blocked(query,n,ray/std::max(length,.001),length,ignored_id))
                        torch_weight=cone*(1-distance/torch_range)*std::max(double(n.dot(-direction)),.12);
                }
            }
        }
        double shot_weight=0;
        if(shot_energy>0&&!e.unlit&&!e.hover_unlit&&!e.unlit_light_id){
            if(!shot_sample||*shot_sample<0){
                Vector3 delta=shot_position-p;
                double square=delta.length_squared(),facing=n.dot(delta);
                if(square<shot_range_squared&&facing>0){
                    double attenuation=1-square/shot_range_squared;
                    shot_weight=attenuation*attenuation*facing/std::max(std::sqrt(square),.001)*
                        nearby_light_visibility(e,p,query,n,shot_position,ignored_id);
                }
                if(shot_sample)*shot_sample=float(shot_weight);
            }else shot_weight=*shot_sample;
        }
        double fog=clamp((-vertex.p.z-fog_start)/std::max(fog_end-fog_start,.001),0,.88);
        Vector3 tint(e.tint.r,e.tint.g,e.tint.b);
        Vector3 transient=tint*(shot_color*(shot_weight*shot_energy)+torch_color*(torch_weight*torch_energy));
        if(e.reflection.page&&!e.hover_unlit){
            double light=clamp((rgb+transient).dot(Vector3(.299,.587,.114))*2.25,0,1);
            vertex.reflection_amount=e.reflection.strength*(1-e.reflection.light_response)*light*(1-fog);
        }
        // Packet colors are bytes, not HDR multipliers. Texture modulation uses 128 as unity.
        double scale=e.textured?128.0:255.0;
        if(entry_cel_mode){
            // Torch and muzzle light stay Gouraud while the room lighting
            // defines the cel bands.
            vertex.cel_light=transient*((1-fog)*scale);
            return Color(rgb.x,rgb.y,rgb.z,flags);
        }else rgb=(rgb+transient).lerp(e.blend_mode==1?Vector3():fog_color,fog);
        for(int i=0;i<3;i++)rgb[i]=clamp(std::floor(rgb[i]*scale),0,255)/255.0;
        return Color(rgb.x,rgb.y,rgb.z,flags);
    }
    static double lamp_weight(const WorldLight &light,Vector3 point,Vector3 &direction){
        if(light.type==2){direction=-light.direction;return light.energy;}
        Vector3 delta=light.position-point;
        double distance=delta.length();
        if(distance>=light.range)return 0;
        direction=delta/std::max(distance,.001);
        double attenuation=1-distance/light.range;
        if(light.type==1){
            double cone=clamp((-direction.dot(light.direction)-light.outer_cos)/std::max(light.inner_cos-light.outer_cos,.000001),0,1);
            attenuation*=cone*cone*(3-2*cone);
        }
        return light.energy*attenuation;
    }
    int reflection_palette_index(Vector3 color){
        int closest=0;
        double error=1e20;
        for(int i=0;i<reflection_light_colors.size();i++){
            double distance=(reflection_light_colors[i]-color).length_squared();
            if(distance<.000001)return i;
            if(distance<error){error=distance;closest=i;}
        }
        if(reflection_light_colors.size()>=32)return closest;
        reflection_light_colors.append(color);
        return reflection_light_colors.size()-1;
    }
    ReflectionLight reflection_source(const Entry &e,const Transform3D &transform,const Basis &normal_matrix,Vector3 view_axis)const{
        const auto &r=e.reflection;
        bool planar=(r.projection==1||r.projection==2)&&!e.skeleton_id;
        Vector3 center=transform.xform(r.bounds.get_center());
        Vector3 normal=planar?normal_matrix.xform(r.projection==1?Vector3(0,0,1):Vector3(0,1,0)).normalized():Vector3();
        if(planar&&normal.dot(orthographic_size>0?view_axis:camera_position-center)<0)normal=-normal;
        double eye_depth=normal.dot(camera_position-center);
        double radius=std::max(e.radius,.01);
        ReflectionLight best;
        auto consider=[&](const WorldLight &source,int index){
            if(source.energy<=0)return;
            Vector3 hit=center;
            bool exact=planar&&source.type!=2;
            if(exact){
                double source_depth=normal.dot(source.position-center);
                if(source_depth<=.001)return;
                // A plane mirror reflects a point as its virtual image on the far side.
                Vector3 virtual_source=source.position-2*source_depth*normal;
                if(orthographic_size>0){
                    double alignment=normal.dot(view_axis);
                    if(alignment<.0001)return;
                    hit=virtual_source+view_axis*(source_depth/alignment);
                }else{
                    if(eye_depth<=.001)return;
                    hit=camera_position.lerp(virtual_source,eye_depth/(eye_depth+source_depth));
                }
                if((hit-center).length()>radius+r.width*.75)return;
            }
            Vector3 direction;
            double intensity=lamp_weight(source,hit,direction);
            if(intensity<=0)return;
            double score=intensity*source.color.dot(Vector3(.299,.587,.114));
            if(planar){
                if(normal.dot(direction)<=0)return;
                if(exact)score/=1+(hit-center).length_squared()/std::max(radius*radius,.1);
                else{
                    Vector3 eye=orthographic_size>0?view_axis:(camera_position-center).normalized();
                    double alignment=(2*normal.dot(eye)*normal-eye).dot(direction);
                    score*=clamp(1-(1-alignment)/std::max(double(r.width)*.22,.035),0,1);
                }
            }
            if(score<=best.score)return;
            if(!e.skeleton_id){
                Vector3 test_normal=planar?normal:direction;
                Vector3 ray=source.type==2?direction:source.position-hit;
                double length=source.type==2?100000:ray.length();
                if(blocked(hit,test_normal,source.type==2?ray:ray.normalized(),length,e.id))return;
            }
            best.source=source;best.center=hit;best.world_index=index;best.score=score;best.planar=exact;
        };
        for(size_t i=0;i<world_lights.size();i++)consider(world_lights[i],int(i));
        if(torch&&e.torch_receiver)
            consider({torch_position,torch_color,torch_direction,torch_energy,torch_range,torch_outer_cos,torch_inner_cos,1},-1);
        if(shot_energy>0)
            consider({shot_position,shot_color,Vector3(),shot_energy,std::sqrt(shot_range_squared),0,1,0},-1);
        return best;
    }
    Vector2 project_reflection(const Entry &e,const ReflectionLight &lamp,size_t i,Vector3 p,Vector3 world,Vector3 normal,Vector3 to_eye,
        const Basis &view_to_local,const Transform3D &local_transform,Vector2 plane_width,double cosine,double sine,Vector3 query,
        uint8_t *visibility,double fog,float &amount)const{
        const auto &r=e.reflection;
        Vector2 uv;
        if(lamp.score>0){
            Vector3 direction;
            double energy=lamp_weight(lamp.source,world,direction);
            double facing=std::max(double(normal.dot(direction)),0.0);
            if(facing>0&&energy>0){
                uint8_t *seen=visibility&&lamp.world_index>=0?visibility+lamp.world_index:nullptr;
                if(!seen||*seen==255){
                    bool directional=lamp.source.type==2;
                    Vector3 ray=directional?direction:lamp.source.position-query;
                    double length=directional?100000:ray.length();
                    bool clear=!blocked(query,normal,directional?ray:ray/std::max(length,.001),length,e.ignore_self_shadow?e.id:0);
                    if(seen)*seen=clear?1:0;
                    if(!clear)energy=0;
                }else if(!*seen)energy=0;
            }else energy=0;
            double response=std::min(energy*1.4/(.7+energy),1.0);
            amount=r.strength*r.light_response*float(response)*float(1-fog);
            if(lamp.planar){
                Vector3 relative=p-local_transform.xform(lamp.center);
                uv=Vector2(.5+relative.x/plane_width.x,.5+(r.projection==1?-relative.y:relative.z)/plane_width.y);
            }else{
                Vector3 reflected=2*normal.dot(to_eye)*normal-to_eye;
                Vector3 reference=std::abs(direction.y)>.92?Vector3(0,0,1):Vector3(0,1,0);
                Vector3 right=reference.cross(direction).normalized();
                Vector3 up=direction.cross(right);
                double span=clamp(r.width*.5,.12,1.0);
                uv=reflected.dot(direction)>0?Vector2(.5+reflected.dot(right)/span,.5-reflected.dot(up)/span):Vector2(-2,-2);
            }
        }else if(r.projection==3){
            Vector3 reflected=rotation.xform(2*normal.dot(to_eye)*normal-to_eye);
            double diameter=2*std::sqrt(std::max(double(reflected.length_squared()+2*reflected.z+1),.00001));
            uv=Vector2(.5+reflected.x/diameter,.5-reflected.y/diameter);
        }else{
            if(r.projection==0){if(!r.mesh_uvs.empty())uv=r.mesh_uvs[i];}
            else{
                Vector3 relative=p-r.bounds.position;
                uv.x=relative.x/std::max(double(r.bounds.size.x),.001);
                uv.y=r.projection==1?1-relative.y/std::max(double(r.bounds.size.y),.001):relative.z/std::max(double(r.bounds.size.z),.001);
            }
            Vector3 local_eye=view_to_local.xform(rotation.xform(to_eye));
            uv+=Vector2(local_eye.x,r.projection==2?local_eye.z:-local_eye.y)*r.motion;
        }
        uv-=Vector2(.5,.5);
        uv=Vector2(cosine*uv.x-sine*uv.y,sine*uv.x+cosine*uv.y)*r.scale+Vector2(.5,.5)+r.offset;
        return Vector2(std::round(uv.x*r.texture_size.x)/r.texture_size.x,std::round(uv.y*r.texture_size.y)/r.texture_size.y);
    }
    void submit(const Vertex &a,const Vertex &b,const Vertex &c,int page_index,int blend_mode,bool cel=false,bool ink=false,int reflection_page=0){
        const Vertex v[3]={a,b,c};Vector2 p[3];double z=0;
        for(int i=0;i<3;i++){
            double divisor=orthographic_size>0?1.0:-v[i].p.z;
            p[i]=Vector2(160+v[i].p.x*focal/divisor,120-v[i].p.y*focal/divisor);
            if(snap){p[i].x=std::floor(p[i].x);p[i].y=std::floor(p[i].y);}
            z-=v[i].p.z/3;
        }
        if((p[1]-p[0]).cross(p[2]-p[0])<=0)return;
        if((p[0].x<0&&p[1].x<0&&p[2].x<0)||(p[0].x>320&&p[1].x>320&&p[2].x>320)||
           (p[0].y<0&&p[1].y<0&&p[2].y<0)||(p[0].y>240&&p[1].y>240&&p[2].y>240))return;
        int bucket=int(clamp(z/far_clip*(ordering_buckets-1),0,ordering_buckets-1));
        Primitive out;out.next=ordering_table[bucket];out.page_index=page_index;out.blend_mode=blend_mode;out.cel_mode=cel?entry_cel_mode:0;out.ink=ink;
        out.silhouette=entry_silhouette&&!ink;out.reflection_page=reflection_page;out.mirror=entry_mirror&&!ink;
        for(int i=0;i<3;i++){
            out.points[i]=p[i];out.colors[i]=v[i].c;out.uvs[i]=v[i].uv;
            out.inverse_depths[i]=orthographic_size>0?1.0f:float(1.0/-v[i].p.z);
            out.depth_scores[i]=orthographic_size>0?float(v[i].p.z):out.inverse_depths[i];
            if(cel)out.cel_lights[i]=v[i].cel_light;
        }
        if(cel)anime_triangles++;
        if(reflection_page)for(int i=0;i<3;i++){out.reflection_uvs[i]=v[i].reflection_uv;out.reflection_amounts[i]=v[i].reflection_amount;}
        ordering_table[bucket]=int(triangles.size());triangles.push_back(out);
    }
    void triangle(const Vertex &a,const Vertex &b,const Vertex &c,int page_index,int blend_mode,bool cel=false,bool ink=false,int reflection_page=0){
        if(capturing_mirror){
            const Vertex input[3]={a,b,c};
            std::array<Vertex,4> clipped;
            int count=0;
            Vertex previous=c;
            double old_distance=previous.p.dot(mirror_view_axis)+mirror_clip_offset;
            for(const auto &current:input){
                double distance=current.p.dot(mirror_view_axis)+mirror_clip_offset;
                if((distance>=0)!=(old_distance>=0)){
                    double t=old_distance/(old_distance-distance);
                    clipped[count++]=clip_vertex(previous,current,t);
                }
                if(distance>=0)clipped[count++]=current;
                previous=current;old_distance=distance;
            }
            for(int j=1;j+1<count;j++)near_triangle(clipped[0],clipped[j],clipped[j+1],page_index,blend_mode,cel,ink,reflection_page);
            return;
        }
        near_triangle(a,b,c,page_index,blend_mode,cel,ink,reflection_page);
    }
    void near_triangle(const Vertex &a,const Vertex &b,const Vertex &c,int page_index,int blend_mode,bool cel,bool ink,int reflection_page){
        if(a.p.z<-near_clip&&b.p.z<-near_clip&&c.p.z<-near_clip){submit(a,b,c,page_index,blend_mode,cel,ink,reflection_page);return;}
        if(a.p.z>=-near_clip&&b.p.z>=-near_clip&&c.p.z>=-near_clip)return;
        const Vertex input[3]={a,b,c};std::array<Vertex,4> clipped;int size=0;Vertex previous=c;
        for(const auto &current:input){
            bool inside=current.p.z<-near_clip,old_inside=previous.p.z<-near_clip;
            if(inside!=old_inside){
                double t=(-near_clip-previous.p.z)/(current.p.z-previous.p.z);
                clipped[size++]=clip_vertex(previous,current,t);
            }
            if(inside)clipped[size++]=current;
            previous=current;
        }
        for(int j=1;j+1<size;j++)submit(clipped[0],clipped[j],clipped[j+1],page_index,blend_mode,cel,ink,reflection_page);
    }
    static Vertex clip_vertex(const Vertex &a,const Vertex &b,double t){
        auto mix=[t](float start,float end){return float(start+(end-start)*t);};
        return {a.p.lerp(b.p,t),a.c.lerp(b.c,t),a.uv.lerp(b.uv,t),a.reflection_uv.lerp(b.reflection_uv,t),
            mix(a.reflection_amount,b.reflection_amount),a.cel_light.lerp(b.cel_light,t)};
    }
    bool anime_actor(const Entry &e)const{return e.depth_correct||(anime.other_characters&&e.anime_character);}
    bool opaque_texel(const Primitive &p,int page,float a,float b,float c)const{
        if(page<=0||page>=atlas_pages.size()||opaque_pages[page]||atlas_rgba.is_empty())return true;
        Vector2 affine=p.uvs[0]*a+p.uvs[1]*b+p.uvs[2]*c,uv=affine;
        if(affine_strength<1){
            float q=a*p.inverse_depths[0]+b*p.inverse_depths[1]+c*p.inverse_depths[2];
            Vector2 perspective=(p.uvs[0]*(a*p.inverse_depths[0])+p.uvs[1]*(b*p.inverse_depths[1])+p.uvs[2]*(c*p.inverse_depths[2]))/q;
            uv=perspective.lerp(affine,affine_strength);
        }
        return opaque_uv(page,uv);
    }
    void update_player_visibility(){
        depth_triangles=0;depth_pixels=0;
        const bool full_depth=capturing_mirror||general_depth||outline_triangles>0;
        int min_x=320,min_y=240,max_x=-1,max_y=-1;
        if(full_depth){min_x=0;min_y=0;max_x=319;max_y=239;depth_triangles=int(triangles.size())-outline_triangles;}
        else for(const auto &p:triangles)if(int(std::round(p.colors[0].a*255))&64){
            depth_triangles++;
            for(const auto &v:p.points){min_x=std::min(min_x,int(std::floor(v.x)));max_x=std::max(max_x,int(std::ceil(v.x)));min_y=std::min(min_y,int(std::floor(v.y)));max_y=std::max(max_y,int(std::ceil(v.y)));}
        }
        min_x=std::max(min_x,0);max_x=std::min(max_x,319);min_y=std::max(min_y,0);max_y=std::min(max_y,239);
        if(!depth_triangles||min_x>max_x||min_y>max_y)return;
        visibility_bytes.resize(320*240*2*sizeof(float));
        auto depth=reinterpret_cast<float *>(visibility_bytes.ptrw());
        for(int i=0;i<320*240;i++){depth[i*2]=-1e20f;depth[i*2+1]=0;}
        player_coverage.fill(0);
        auto rasterize=[&](const Primitive &p,bool actor){
            // The shell may add pixels outside the silhouette. It must never
            // enter the solid depth/coverage pass and hide the model itself.
            if(p.ink)return;
            int flags=int(std::round(p.colors[0].a*255));
            // Translucent flashes are tested against solids, but never hide them.
            if((!actor||full_depth)&&(flags&32))return;
            int x0=max_x,y0=max_y,x1=min_x,y1=min_y;
            for(const auto &v:p.points){x0=std::min(x0,int(std::floor(v.x)));y0=std::min(y0,int(std::floor(v.y)));x1=std::max(x1,int(std::ceil(v.x)));y1=std::max(y1,int(std::ceil(v.y)));}
            x0=std::max(x0,min_x);x1=std::min(x1,max_x);y0=std::max(y0,min_y);y1=std::min(y1,max_y);
            if(x0>x1||y0>y1)return;
            Vector2 ab=p.points[1]-p.points[0],ac=p.points[2]-p.points[0],bc=p.points[2]-p.points[1];
            float inv_area=1.0f/ab.cross(ac);
            auto top_left=[](Vector2 edge){return edge.y<0||(edge.y==0&&edge.x>0);};
            bool edge_a=top_left(bc),edge_b=top_left(-ac),edge_c=top_left(ab);
            int step=capturing_mirror?2:1;
            if(capturing_mirror){x0|=1;y0|=1;}
            for(int y=y0;y<=y1;y+=step)for(int x=x0;x<=x1;x+=step){
                int at=y*320+x;if(!full_depth&&!actor&&!player_coverage[at])continue;
                float center=capturing_mirror?0:.5f;
                Vector2 point=Vector2(x+center,y+center)-p.points[0];
                float wa=bc.cross(point-ab),wb=point.cross(ac),wc=ab.cross(point);
                if(wa<0||wb<0||wc<0||(wa==0&&!edge_a)||(wb==0&&!edge_b)||(wc==0&&!edge_c))continue;
                float a=wa*inv_area,b=wb*inv_area,c=wc*inv_area;
                if((actor||full_depth)&&!player_coverage[at]){player_coverage[at]=1;depth_pixels++;}
                if(flags&32)continue;
                float score=a*p.depth_scores[0]+b*p.depth_scores[1]+c*p.depth_scores[2];
                if(score<depth[at*2]||(!actor&&score==depth[at*2]))continue;
                if(!opaque_texel(p,p.page_index,a,b,c))continue;
                depth[at*2]=score;
                depth[at*2+1]=float((actor?1:0)|(p.silhouette?2:0));
            }
        };
        if(full_depth){
            for(const auto &p:triangles)rasterize(p,(int(std::round(p.colors[0].a*255))&64)!=0);
        }else{
            for(int bucket=ordering_buckets-1;bucket>=0;bucket--)for(int i=ordering_table[bucket];i!=-1;i=triangles[i].next)
                if(int(std::round(triangles[i].colors[0].a*255))&64)rasterize(triangles[i],true);
            for(const auto &p:triangles)if(!(int(std::round(p.colors[0].a*255))&64))rasterize(p,false);
        }
        if(!depth_pixels)return;
        auto &image=capturing_mirror?mirror_visibility_image:visibility_image;
        auto &texture=capturing_mirror?mirror_visibility_texture:visibility_texture;
        if(image.is_null())image.instantiate();
        image->set_data(320,240,false,Image::FORMAT_RGF,visibility_bytes);
        if(texture.is_null())texture=ImageTexture::create_from_image(image);
        else texture->update(image);
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("configure","entries"),&PSXGeometry::configure);
        ClassDB::bind_method(D_METHOD("frame","camera","fov","torch","power","snap"),&PSXGeometry::frame);
        ClassDB::bind_method(D_METHOD("get_statistics"),&PSXGeometry::get_statistics);
        ClassDB::bind_method(D_METHOD("get_player_depth_texture"),&PSXGeometry::get_player_depth_texture);
        ClassDB::bind_method(D_METHOD("get_depth_texture"),&PSXGeometry::get_player_depth_texture);
        ClassDB::bind_method(D_METHOD("set_render_settings","settings"),&PSXGeometry::set_render_settings);
        ClassDB::bind_method(D_METHOD("set_shot_light","position","color","energy","range"),&PSXGeometry::set_shot_light);
        ClassDB::bind_method(D_METHOD("set_torch_light","position","direction","color","energy","range","outer_cos","inner_cos"),&PSXGeometry::set_torch_light);
        ClassDB::bind_method(D_METHOD("set_world_lights","lights","ambient"),&PSXGeometry::set_world_lights);
        ClassDB::bind_method(D_METHOD("get_reflection_light_colors"),&PSXGeometry::get_reflection_light_colors);
        ClassDB::bind_method(D_METHOD("get_mirror_depth_texture"),&PSXGeometry::get_mirror_depth_texture);
        ClassDB::bind_method(D_METHOD("set_mirror_surface","node","surface"),&PSXGeometry::set_mirror_surface);
        ClassDB::bind_method(D_METHOD("mirror_frame","camera","fov","torch","power","snap","point","normal"),&PSXGeometry::mirror_frame);
        ClassDB::bind_method(D_METHOD("set_unlit_overrides","mesh_ids"),&PSXGeometry::set_unlit_overrides);
        ClassDB::bind_method(D_METHOD("set_anime_settings","settings"),&PSXGeometry::set_anime_settings);
    }
public:
    void set_anime_settings(Dictionary settings){
        anime.enabled=settings.get("enabled",false);anime.strength=clamp(double(settings.get("strength",1.0)),0,1);
        anime.world_strength=clamp(double(settings.get("world_strength",0.0)),0,1);
        anime.other_characters=settings.get("other_characters",true);
        anime.outline_enabled=settings.get("outline_enabled",true);anime.outline_width=clamp(double(settings.get("outline_width",.006)),0,.03);
        anime.outline_color=settings.get("outline_color",Vector3(.025,.02,.04));
    }
    void set_unlit_overrides(const PackedInt64Array &ids){
        std::unordered_set<uint64_t> selected;
        for(int i=0;i<ids.size();i++)selected.insert(uint64_t(ids[i]));
        for(auto &entry:entries){
            bool hover=selected.count(entry.id)!=0;
            if(entry.hover_unlit&&!hover)entry.light_revision=0;
            entry.hover_unlit=hover;
        }
    }
    void set_world_lights(Array lights,Vector3 ambient){
        auto previous=world_lights;
        world_lights.clear();world_lights.reserve(lights.size());ambient_light=ambient;
        fixture_emissions.clear();
        for(int i=0;i<lights.size();i++){
            Dictionary source=lights[i];WorldLight light;
            light.position=source.get("position",Vector3());light.color=source.get("color",Vector3(1,1,1));
            light.id=source.get("id",int64_t(i));
            fixture_emissions.emplace(light.id,Vector3(source.get("fixture_emission",Vector3())));
            light.type=std::clamp(int(source.get("type",0)),0,2);
            light.direction=Vector3(source.get("direction",Vector3(0,0,-1))).normalized();
            light.outer_cos=double(source.get("outer_cos",.9));light.inner_cos=std::max(double(source.get("inner_cos",.95)),light.outer_cos+.000001);
            light.energy=std::max(double(source.get("energy",1.0)),0.0);light.range=std::max(double(source.get("range",6.0)),.001);
            world_lights.push_back(light);
        }
        bool changed=previous.size()!=world_lights.size();
        if(!changed)for(size_t i=0;i<previous.size();i++){
            const auto &a=previous[i];const auto &b=world_lights[i];
            if(a.id!=b.id||a.position!=b.position||a.direction!=b.direction||a.type!=b.type||a.range!=b.range||a.inner_cos!=b.inner_cos||a.outer_cos!=b.outer_cos){changed=true;break;}
        }
        if(changed)visibility_revision++;
        lighting_configured=true;lighting_revision++;
    }
    void set_torch_light(Vector3 position,Vector3 direction,Vector3 color,double energy,double range,double outer_cos,double inner_cos){
        torch_position=position;torch_direction=direction.normalized();torch_color=color;
        torch_energy=std::max(energy,0.0);torch_range=std::max(range,.001);
        torch_outer_cos=outer_cos;torch_inner_cos=std::max(inner_cos,outer_cos+.000001);
    }
    void set_shot_light(Vector3 position,Vector3 color,double energy,double range){
        double range_squared=std::max(range*range,.0001);
        if(position!=shot_position||range_squared!=shot_range_squared)shot_revision++;
        shot_position=position;shot_color=color;shot_energy=std::max(energy,0.0);shot_range_squared=range_squared;
    }
    void set_render_settings(Dictionary settings){
        general_depth=settings.get("depth_correction",true);
        bool shadows=settings.get("light_occlusion",true);
        if(shadows!=light_occlusion){light_occlusion=shadows;visibility_revision++;lighting_revision++;}
        far_clip=std::max(double(settings.get("far_clip",42.0)),1.0);
        near_clip=std::max(double(settings.get("near_clip",.1)),.001);
        fog_start=double(settings.get("fog_start",9.0));fog_end=double(settings.get("fog_end",33.0));
        fog_color=settings.get("fog_color",Vector3(.027,.044,.046));
        orthographic_size=std::max(double(settings.get("orthographic_size",0.0)),0.0);
        affine_strength=clamp(double(settings.get("affine_texture_strength",1.0)),0,1);
        ordering_buckets=std::max(int(settings.get("ordering_buckets",1024)),16);
        ordering_table.resize(ordering_buckets);
    }
    Dictionary get_statistics()const{
        Dictionary d;d["version"]=29;d["triangles"]=int(triangles.size());d["source_triangles"]=int(triangles.size());d["anime_source_triangles"]=anime_triangles;d["anime_triangles"]=anime_triangles;d["outline_triangles"]=outline_triangles;d["frame_us"]=frame_us;d["vertices"]=vertices_processed;d["batches"]=batch_count;d["shot_light_energy"]=shot_energy;d["world_lights"]=int(world_lights.size());d["light_revision"]=int64_t(lighting_revision);d["player_depth_triangles"]=depth_triangles;d["player_depth_pixels"]=depth_pixels;d["depth_pixels"]=depth_pixels;d["general_depth"]=general_depth;d["light_occluders"]=int(occluders.size());d["shadow_rays"]=int64_t(shadow_rays);d["shadow_triangle_tests"]=int64_t(shadow_triangle_tests);return d;
    }
    Ref<ImageTexture> get_player_depth_texture()const{return visibility_texture;}
    Ref<ImageTexture> get_mirror_depth_texture()const{return depth_pixels>0?mirror_visibility_texture:Ref<ImageTexture>();}
    PackedVector3Array get_reflection_light_colors()const{
        PackedVector3Array colors=reflection_light_colors;
        colors.resize(32);
        return colors;
    }
    void configure(Array input){
        entries.clear();size_t primitive_capacity=0;atlas_rgba.clear();atlas_pages.clear();
        shot_samples.clear();shot_samples.resize(input.size());
        occluders_dirty=true;opaque_pages.clear();has_reflection_pages=false;
        for(int i=0;i<input.size();i++){
            Dictionary d=input[i];Entry e;
            e.light_revision=lighting_configured?0:lighting_revision;
            Object *node=d["node"];e.id=node->get_instance_id();
            e.surface=d.get("surface",0);
            Object *skeleton=d["skeleton"];if(skeleton)e.skeleton_id=skeleton->get_instance_id();
            e.vertices=copy<Vector3>(PackedVector3Array(d["vertices"]));
            if(d["normals"].get_type()!=Variant::NIL)e.normals=copy<Vector3>(PackedVector3Array(d["normals"]));
            e.indices=copy<int32_t>(PackedInt32Array(d["indices"]));
            e.bind_indices=copy<int32_t>(PackedInt32Array(d["bind_indices"]));
            if(e.skeleton_id){e.bones=copy<int32_t>(PackedInt32Array(d["bones"]));e.weights=copy<float>(PackedFloat32Array(d["weights"]));e.influences=e.vertices.empty()?0:int(e.bones.size()/e.vertices.size());}
            Array binds=d["binds"];for(int b=0;b<binds.size();b++)e.binds.push_back(binds[b]);e.skin.resize(e.binds.size());
            e.tint=d["color"];e.emission=d["emission"];e.fixed=d["fixed"];
            e.textured=d.get("textured",false);e.sprite=d.get("sprite",false);e.depth_correct=d.get("depth_correct",false);e.page=d.get("texture_page",0);atlas=d["draw_texture"];
            e.page_index=d.get("page_index",e.page&31);
            e.unlit_light_id=d.get("unlit_light_id",int64_t(0));
            e.unlit=d.get("unlit",false);
            e.anime_character=d.get("anime_character",false);
            e.blend_mode=int(d.get("blend_mode",0))==1?1:0;
            e.light_occluder=d.get("light_occluder",false);e.light_receiver=d.get("light_static_receiver",e.light_occluder);e.torch_receiver=d.get("torch_receiver",true);
            e.ignore_self_shadow=d.get("ignore_self_shadow",false);
            if(e.unlit)e.light_receiver=false;
            if(i==0){
                atlas_pages=d.get("atlas_pages",PackedVector4Array());
                opaque_pages.assign(atlas_pages.size(),true);
                Ref<Image> image=atlas->get_image();
                if(image.is_valid()){if(image->is_compressed())image->decompress();image->convert(Image::FORMAT_RGBA8);atlas_rgba=image->get_data();atlas_width=image->get_width();}
                for(int page=1;page<atlas_pages.size();page++){
                    const auto &r=atlas_pages[page];
                    for(int y=0;y<int(r.w)&&opaque_pages[page];y++)for(int x=0;x<int(r.z);x++){
                        size_t at=(size_t(int(r.y)+y)*atlas_width+int(r.x)+x)*4+3;
                        if(at<size_t(atlas_rgba.size())&&atlas_rgba[at]<128){opaque_pages[page]=false;break;}
                    }
                }
            }
            e.face_part=d.get("face_part",0);
            PackedInt32Array face_pages=d.get("face_pages",PackedInt32Array());
            if(face_pages.size()==2){e.face_pages[0]=face_pages[0];e.face_pages[1]=face_pages[1];}else e.face_part=0;
            e.static_positions=copy<Vector3>(PackedVector3Array(d["static_positions"]));
            e.static_normals=copy<Vector3>(PackedVector3Array(d["static_normals"]));
            e.static_light=copy<Vector3>(PackedVector3Array(d["static_light"]));
            Vector2 texture_size=d["logical_texture_size"];
            e.uvs.resize(e.vertices.size());
            if(d["uvs"].get_type()!=Variant::NIL){
                PackedVector2Array data=d["uvs"];const Vector2 *uv=data.ptr();
                for(size_t v=0;v<e.uvs.size();v++)e.uvs[v]=Vector2(std::round(uv[v].x*(texture_size.x-1))/texture_size.x,std::round(uv[v].y*(texture_size.y-1))/texture_size.y);
            }
            auto &r=e.reflection;
            int reflection_page=d.get("reflection_page",0);
            r.scene=d.get("scene_reflection",0.0);
            has_reflection_pages|=r.scene>0;
            if(reflection_page>0&&reflection_page<atlas_pages.size()){
                r.page=reflection_page;
                r.texture_size=Vector2(atlas_pages[r.page].z,atlas_pages[r.page].w);
                r.projection=d.get("reflection_projection",0);
                r.strength=d.get("reflection_strength",0.0);
                r.light_response=d.get("reflection_light_response",0.0);
                r.motion=d.get("reflection_motion",0.0);
                r.width=d.get("reflection_width",1.15);
                r.scale=d.get("reflection_scale",1.0);
                r.angle=d.get("reflection_angle",0.0);
                r.offset=d.get("reflection_offset",Vector2());
                r.bounds=d.get("reflection_bounds",AABB());
                if(r.projection==0&&d["uvs"].get_type()!=Variant::NIL)
                    r.mesh_uvs=copy<Vector2>(PackedVector2Array(d["uvs"]));
                has_reflection_pages=true;
            }
            auto mesh=Object::cast_to<MeshInstance3D>(node);e.fixed_transform=mesh->get_global_transform();
            AABB aabb=d["aabb"];e.local_center=aabb.get_center();e.center=e.fixed_transform.xform(e.local_center);
            Vector3 scale=e.fixed_transform.basis.get_scale();e.radius=aabb.size.length()*.5*std::max({scale.x,scale.y,scale.z});
            e.projected.resize(e.vertices.size());if(e.depth_correct||e.anime_character)e.ink_projected.resize(e.vertices.size());primitive_capacity+=e.indices.size()/3;
            entries.push_back(std::move(e));
        }
        triangles.reserve(primitive_capacity+64);ordering_table.resize(ordering_buckets);
    }
    Array frame(Transform3D camera,double fov,bool torch_enabled,bool power_enabled,bool snap_enabled){
        auto frame_start=std::chrono::steady_clock::now();
        power=power_enabled;torch=torch_enabled;snap=snap_enabled;
        inverse=camera.affine_inverse();rotation=inverse.basis;
        for(int i=0;i<3;i++)rotation.set_column(i,quantize(rotation.get_column(i),4096));
        focal=orthographic_size>0?240/orthographic_size:120/std::tan(fov*3.141592653589793/360);
        camera_position=camera.origin;
        Vector3 view_axis=camera.basis.get_column(2).normalized();
        if(has_reflection_pages){reflection_light_colors.clear();reflection_light_colors.append(Vector3(1,1,1));}
        triangles.clear();vertices_processed=0;anime_triangles=0;outline_triangles=0;std::fill(ordering_table.begin(),ordering_table.end(),-1);
        shadow_rays=0;shadow_triangle_tests=0;update_occluders();
        for(size_t entry_index=0;entry_index<entries.size();entry_index++){
            auto &e=entries[entry_index];
            e.ink_frame_ready=false;
            if(capturing_mirror&&((e.id==mirror_node&&e.surface==mirror_surface)||e.sprite||e.blend_mode==1))continue;
            auto node=Object::cast_to<MeshInstance3D>(UtilityFunctions::instance_from_id(e.id));
            if(!node||!node->is_visible_in_tree())continue;
            Transform3D transform=e.fixed?e.fixed_transform:node->get_global_transform();
            if(e.fixed||capturing_mirror){
                Vector3 world_center=e.fixed?e.center:transform.xform(e.local_center);
                Vector3 center=inverse.xform(world_center);double depth=-center.z;
                double mirror_range=10.0+e.radius;
                if(capturing_mirror&&world_center.distance_squared_to(mirror_plane_center)>mirror_range*mirror_range)continue;
                double extent=orthographic_size>0?1.0:depth;
                if(depth+e.radius<near_clip||depth-e.radius>far_clip||std::abs(center.x)>extent*160/focal+e.radius||std::abs(center.y)>extent*120/focal+e.radius)continue;
            }
            auto skeleton=e.skeleton_id?Object::cast_to<Skeleton3D>(UtilityFunctions::instance_from_id(e.skeleton_id)):nullptr;
            if(skeleton){
                Transform3D skeleton_world=skeleton->get_global_transform();
                for(size_t i=0;i<e.binds.size();i++)e.skin[i]=skeleton_world*skeleton->get_bone_global_pose(e.bind_indices[i])*e.binds[i];
            }
            Basis normal_matrix=e.fixed?Basis():transform.basis.inverse().transposed();
            Vector3 receiver_center=transform.xform(e.local_center);
            if(e.light_receiver&&(e.visibility_revision!=visibility_revision||e.receiver_transform!=transform)){
                e.light_visibility.assign(e.vertices.size()*world_lights.size(),255);e.visibility_revision=visibility_revision;e.receiver_transform=transform;
            }
            float *cached_shot=nullptr;
            if(shot_energy>0&&!e.skeleton_id&&!e.unlit&&!e.sprite&&!e.unlit_light_id)
                cached_shot=shot_samples[entry_index].prepare(shot_revision+visibility_revision,transform,e.vertices.size());
            bool relight=e.light_revision!=lighting_revision;
            bool character=anime_actor(e);
            bool eligible=anime.enabled&&!e.unlit&&!e.hover_unlit&&!e.unlit_light_id&&!e.sprite&&e.blend_mode==0&&!(e.page&32);
            bool actor=eligible&&character;
            entry_silhouette=anime.enabled&&anime.outline_enabled&&anime.outline_width>0&&character;
            entry_cel_mode=actor&&anime.strength>0?1:(eligible&&!actor&&!e.anime_character&&anime.world_strength>0?2:0);
            bool ink=actor&&anime.outline_enabled&&anime.outline_width>0&&skeleton;
            e.ink_frame_ready=ink;
            int sprite_frame=e.sprite?int(node->get_meta("psx_sprite_frame",0)):0;
            int face_frame=e.face_part?int(clamp(int64_t(node->get_meta(e.face_part==1?"psx_face_top_frame":"psx_face_bottom_frame",0)),0,7)):0;
            Vector3 unlit_color=(e.unlit||e.hover_unlit)?Vector3(e.tint.r,e.tint.g,e.tint.b):Vector3();
            if(e.unlit_light_id&&!e.hover_unlit){auto source=fixture_emissions.find(e.unlit_light_id);if(source!=fixture_emissions.end())unlit_color=Vector3(e.tint.r,e.tint.g,e.tint.b)*source->second;}
            if(e.face_part){e.page_index=e.face_pages[face_frame/4];e.page=(e.page&~31)|(e.page_index&31);}
            const auto &reflection=e.reflection;
            int reflection_page=(e.hover_unlit||capturing_mirror)?0:reflection.page;
            entry_mirror=!e.hover_unlit&&!capturing_mirror&&reflection.scene>0&&e.id==mirror_node&&e.surface==mirror_surface;
            Basis view_to_local;
            Transform3D reflection_local;
            ReflectionLight reflection_lamp;
            Vector2 reflection_width(1,1);
            double reflection_cosine=1,reflection_sine=0;
            if(reflection_page){
                Basis reflection_normal_matrix=e.fixed?transform.basis.inverse().transposed():normal_matrix;
                if(reflection.light_response>0)reflection_lamp=reflection_source(e,transform,reflection_normal_matrix,view_axis);
                if(reflection_lamp.score>0)reflection_lamp.palette_index=reflection_palette_index(reflection_lamp.source.color);
                else if(reflection.light_response>=1)reflection_page=0;
                if(reflection_lamp.planar){
                    reflection_local=transform.affine_inverse();
                    Vector3 scale=transform.basis.get_scale().abs();
                    reflection_width=Vector2(reflection.width/std::max(double(scale.x),.001),
                        reflection.width/std::max(double(reflection.projection==1?scale.y:scale.z),.001));
                }
                if(reflection.projection!=3&&reflection.motion!=0)
                    view_to_local=transform.basis.orthonormalized().transposed()*camera.basis;
                reflection_cosine=std::cos(reflection.angle);
                reflection_sine=std::sin(reflection.angle);
                if(reflection_page)reflection_page=reflection_page*32+reflection_lamp.palette_index;
            }
            for(size_t i=0;i<e.vertices.size();i++){
                Vector3 world_pos,world_normal;
                if(e.fixed){world_pos=e.static_positions[i];world_normal=e.static_normals[i];}
                else{
                    Vector3 p=e.vertices[i],n=e.normals.empty()?Vector3(0,1,0):e.normals[i];
                    if(skeleton){
                        for(int w=0;w<e.influences;w++){
                            int bone=e.bones[i*e.influences+w];double weight=e.weights[i*e.influences+w];
                            if(weight>0&&bone<int(e.skin.size())){world_pos+=e.skin[bone].xform(p)*weight;world_normal+=e.skin[bone].basis.xform(n)*weight;}
                        }
                    }else{world_pos=transform.xform(p);world_normal=normal_matrix.xform(n);}
                    if(ink){
                        Vector3 shell_pos=quantize(world_pos+world_normal*anime.outline_width,1024);
                        Vector3 shell_view=quantize(rotation.xform(shell_pos-camera_position),1024,false);
                        Vector3 color=anime.outline_color.lerp(fog_color,clamp((-shell_view.z-fog_start)/std::max(fog_end-fog_start,.001),0,.88));
                        e.ink_projected[i]={shell_view,Color(clamp(std::floor(color.x*255),0,255)/255,clamp(std::floor(color.y*255),0,255)/255,clamp(std::floor(color.z*255),0,255)/255,float(128|(e.depth_correct?64:0))/255),Vector2()};
                    }
                    world_pos=quantize(world_pos,1024);world_normal.normalize();
                }
                Vector3 view=quantize(rotation.xform(world_pos-camera_position),1024,false);
                // Floor tiles on opposite sides of a wall share boundary
                // coordinates. Sample just inside each receiving surface so
                // those vertices do not leak the neighbouring room's light.
                Vector3 sample=world_pos;
                if(e.light_receiver){Vector3 tangent=receiver_center-world_pos;tangent-=world_normal*tangent.dot(world_normal);double length=tangent.length();if(length>1e-5)sample+=tangent/length*std::min(std::abs(world_normal.y)>.8?.16:.008,length*.25);}
                Vector3 base;
                uint8_t *visibility=e.light_receiver&&!world_lights.empty()?e.light_visibility.data()+i*world_lights.size():nullptr;
                if(e.unlit||e.hover_unlit||e.unlit_light_id||e.sprite)base=unlit_color;
                else if(e.fixed){if(relight)e.static_light[i]=bake(world_pos,world_normal,e.tint,e.emission,visibility,&sample,e.ignore_self_shadow?e.id:0);base=e.static_light[i];}
                else base=bake(world_pos,world_normal,e.tint,e.emission,visibility,&sample,e.ignore_self_shadow?e.id:0);
                Vector2 uv=e.uvs[i];
                if(e.face_part)uv=uv*.5+Vector2((face_frame%2)*.5,((face_frame%4)/2)*.5);
                if(e.sprite)uv=Vector2((std::round(uv.x*63)+(sprite_frame%4)*64)/256.0,(std::round(uv.y*63)+(sprite_frame/4)*64)/256.0);
                auto &projected=e.projected[i];
                projected.p=view;
                projected.uv=uv;
                projected.reflection_amount=0;
                projected.c=shade(world_pos,world_normal,e,base,sample,projected,cached_shot?cached_shot+i:nullptr);
                if(reflection_page){
                    Vector3 to_eye=orthographic_size>0?view_axis:(camera_position-world_pos).normalized();
                    projected.reflection_uv=project_reflection(e,reflection_lamp,i,e.vertices[i],world_pos,world_normal,
                        to_eye,view_to_local,reflection_local,reflection_width,reflection_cosine,reflection_sine,sample,
                        visibility,clamp((-view.z-fog_start)/std::max(fog_end-fog_start,.001),0,.88),projected.reflection_amount);
                }
            }
            e.light_revision=lighting_revision;vertices_processed+=int(e.vertices.size());
            for(size_t i=0;i+2<e.indices.size();i+=3)triangle(e.projected[e.indices[i]],e.projected[e.indices[i+1]],e.projected[e.indices[i+2]],e.page_index,e.blend_mode,entry_cel_mode!=0,false,reflection_page);
        }
        for(const auto &e:entries)if(e.ink_frame_ready){
            size_t first=triangles.size();
            for(size_t i=0;i+2<e.indices.size();i+=3)triangle(e.ink_projected[e.indices[i]],e.ink_projected[e.indices[i+2]],e.ink_projected[e.indices[i+1]],0,0,false,true);
            outline_triangles+=int(triangles.size()-first);
        }
        update_player_visibility();
        // Preserve bucket/LIFO order. Split only when the blend equation changes.
        Array output;batch_count=0;ordered_triangles.clear();ordered_triangles.reserve(triangles.size());
        for(int bucket=ordering_buckets-1;bucket>=0;bucket--)
            for(int index=ordering_table[bucket];index!=-1;index=triangles[index].next)ordered_triangles.push_back(index);
        bool extended_pages=atlas_pages.size()>32||capturing_mirror;
        bool reflection_channels=has_reflection_pages&&!capturing_mirror;
        bool cel_channels=anime_triangles>0;
        int stride=(extended_pages||has_reflection_pages||cel_channels)?4:2;
        int uv_stride=reflection_channels||cel_channels?4:2;
        for(size_t first=0;first<ordered_triangles.size();){
            int mode=triangles[ordered_triangles[first]].blend_mode;size_t last=first+1;
            while(last<ordered_triangles.size()&&triangles[ordered_triangles[last]].blend_mode==mode)last++;
            int count=int(last-first)*3;
            PackedVector2Array points,uvs;PackedColorArray colors;PackedInt32Array indices;PackedFloat32Array inverse_depths,depth_channels,perspective_uvs;
            points.resize(count);uvs.resize(count);colors.resize(count);indices.resize(count);inverse_depths.resize(count);depth_channels.resize(count*stride);perspective_uvs.resize(count*uv_stride);
            auto pp=points.ptrw();auto pu=uvs.ptrw();auto pc=colors.ptrw();auto pi=indices.ptrw();auto pq=inverse_depths.ptrw();auto pd=depth_channels.ptrw();auto pv=perspective_uvs.ptrw();int at=0;
            for(size_t index=first;index<last;index++){
                const auto &p=triangles[ordered_triangles[index]];
                for(int j=0;j<3;j++,at++){
                    pp[at]=p.points[j];pu[at]=p.uvs[j];pc[at]=p.colors[j];pi[at]=at;pq[at]=p.inverse_depths[j];
                    pd[at*stride]=p.inverse_depths[j];pd[at*stride+1]=p.depth_scores[j];
                    if(cel_channels){
                        if(p.cel_mode){
                            auto encode=[](double channel){return int(clamp(std::round(channel*.25),0,255));};
                            auto encode_base=[](double channel){return int(clamp(std::round(channel*127.5),0,255));};
                            const auto &light=p.cel_lights[j];
                            const auto &color=p.colors[j];
                            pv[at*uv_stride]=float(encode(light.x)|(encode(light.y)<<8)|(encode(light.z)<<16));
                            pv[at*uv_stride+1]=float(encode_base(color.r)|(encode_base(color.g)<<8)|(encode_base(color.b)<<16));
                            // RGB stays within the packed color range; alpha
                            // still owns the original PSX page and flags.
                            pc[at]=Color(0,0,0,color.a);
                        }else{
                            pv[at*uv_stride]=0;
                            pv[at*uv_stride+1]=0;
                        }
                    }else{
                        Vector2 uvq=p.uvs[j]*p.inverse_depths[j];
                        pv[at*uv_stride]=uvq.x;pv[at*uv_stride+1]=uvq.y;
                    }
                    if(stride==4){
                        pd[at*stride+2]=float(p.page_index)+float(p.cel_mode)*.125f;
                        // One channel carries the constant page and interpolated weight.
                        float reflection_data=p.reflection_page?p.reflection_page+.125f+.25f*p.reflection_amounts[j]:0;
                        pd[at*stride+3]=p.mirror?-std::max(reflection_data,1.0f):reflection_data;
                    }
                    if(uv_stride==4){
                        pv[at*uv_stride+2]=p.reflection_page?p.reflection_uvs[j].x:0;
                        pv[at*uv_stride+3]=p.reflection_page?p.reflection_uvs[j].y:0;
                    }
                }
            }
            Dictionary d;d["points"]=points;d["uvs"]=uvs;d["colors"]=colors;d["indices"]=indices;d["inverse_depths"]=inverse_depths;d["depth_channels"]=depth_channels;d["perspective_uvs"]=perspective_uvs;d["extended_pages"]=extended_pages;d["reflection_channels"]=reflection_channels;d["texture"]=atlas;d["blend_mode"]=mode;
            d["cel_channels"]=cel_channels;
            output.append(d);first=last;
        }
        batch_count=int(output.size());
        frame_us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-frame_start).count();
        return output;
    }
    void set_mirror_surface(uint64_t node,int surface){mirror_node=node;mirror_surface=surface;}
    Array mirror_frame(Transform3D camera,double fov,bool torch_enabled,bool power_enabled,bool snap_enabled,Vector3 point,Vector3 normal){
        capturing_mirror=true;
        mirror_plane_center=point;
        mirror_view_axis=camera.basis.transposed().xform(normal);
        mirror_clip_offset=(camera.origin-point).dot(normal)-.002;
        Array output=frame(camera,fov,torch_enabled,power_enabled,snap_enabled);
        capturing_mirror=false;
        return output;
    }
};
void register_psx_audio();
void initialize_psx(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE){ClassDB::register_class<PSXGeometry>();register_psx_audio();}}
void uninitialize_psx(ModuleInitializationLevel level){}
extern "C" GDExtensionBool GDE_EXPORT psx_library_init(GDExtensionInterfaceGetProcAddress get_proc,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){
    GDExtensionBinding::InitObject init(get_proc,library,initialization);
    init.register_initializer(initialize_psx);init.register_terminator(uninitialize_psx);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
