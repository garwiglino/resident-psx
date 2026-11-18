shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D world_depth : filter_nearest, repeat_disable;
uniform bool depth_enabled = false;
varying float score;
void vertex() { score = COLOR.r; }
void fragment() {
    if (texture(TEXTURE,UV).a < 0.5) { discard; }
    if (depth_enabled) {
        float visible = texelFetch(world_depth,clamp(ivec2(FRAGCOORD.xy),ivec2(0),ivec2(319,239)),0).r;
        if (score + max(0.00001,abs(visible)*0.0002) < visible) { discard; }
    }
    COLOR = vec4(1.0);
}
