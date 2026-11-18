uniform bool dither_enabled = true;
uniform float affine_texture_strength : hint_range(0.0,1.0) = 1.0;
uniform float flash_opacity : hint_range(0.0,1.0) = 0.5;
uniform bool player_depth_correction = false;
uniform bool world_depth_correction = false;
uniform sampler2D player_depth_texture : filter_nearest, repeat_disable;
uniform vec4 texture_pages[32]; // x,y = atlas origin; z,w = logical texture/window size
uniform bool extended_texture_pages = false;
uniform bool explicit_perspective_uvs = false;
uniform bool reflections_enabled = false;
uniform vec3 reflection_light_colors[32];
uniform bool mirror_enabled = false;
uniform float mirror_mix : hint_range(0.0,1.0) = 0.8;
uniform sampler2D mirror_texture : filter_nearest, repeat_disable;
uniform float raster_pixel_scale = 1.0;
uniform sampler2D texture_page_lookup : filter_nearest, repeat_disable;
uniform bool cel_enabled = false;
uniform vec3 cel_thresholds;
uniform vec3 cel_levels;
uniform vec3 cel_shadow_tint;
uniform vec3 cel_light_tint;
uniform vec2 cel_strength;
uniform float cel_darkness_multiplier;
uniform float cel_hue_retention;
uniform bool cel_three_tones = false;
uniform vec3 cel_fog_color;
uniform vec2 cel_fog_range;
uniform float cel_orthographic_size = 0.0;
varying flat float logical_page;
varying vec4 packet_color;
varying vec3 perspective_uvq;
varying float visibility_score;
varying float visibility_valid;
varying vec2 reflection_uv;
varying vec2 reflection_uvq;
varying float reflection_packet;
varying flat float cel_mode;
varying vec3 cel_dynamic_light;
varying vec3 cel_base_light;
const float DITHER[16] = float[16](
    -4.0, 0.0,-3.0, 1.0,
     2.0,-2.0, 3.0,-1.0,
    -3.0, 1.0,-4.0, 0.0,
     3.0,-1.0, 2.0,-2.0
);
void vertex() {
    // Byte RGB from the packet; alpha carries the page index and translucent flag.
    // Canvas uses w=1: both this color and UV are interpolated affinely on screen.
    packet_color = COLOR;
    float inverse_depth = max(CUSTOM0.x,0.00000001);
    perspective_uvq = vec3(explicit_perspective_uvs && !cel_enabled ? CUSTOM1.xy : UV * inverse_depth,inverse_depth);
    visibility_score = CUSTOM0.y;
    visibility_valid = step(0.00000001,CUSTOM0.x);
    logical_page = CUSTOM0.z;
    reflection_uv = CUSTOM1.zw;
    reflection_uvq = reflection_uv * inverse_depth;
    reflection_packet = CUSTOM0.w;
    // With native cel packets, the page's fractional bits select the
    // palette. Decode the two RGB values before Gouraud interpolation.
    cel_mode = cel_enabled ? fract(CUSTOM0.z) * 8.0 : 0.0;
    cel_dynamic_light = vec3(0.0);
    cel_base_light = vec3(0.0);
    if (cel_mode > 0.0) {
        int light = int(CUSTOM1.x);
        cel_dynamic_light = vec3(float(light & 255),float((light >> 8) & 255),float((light >> 16) & 255)) * 4.0;
        int base = int(CUSTOM1.y);
        cel_base_light = vec3(float(base & 255),float((base >> 8) & 255),float((base >> 16) & 255)) * (2.0 / 255.0);
    }
}
void fragment() {
    int packet_flags = clamp(int(floor(packet_color.a * 255.0 + 0.5)),0,255);
    int page_index = extended_texture_pages ? int(floor(logical_page + (cel_enabled ? 0.0 : 0.5))) : packet_flags & 31;
    vec3 vertex_rgb8 = floor(clamp(packet_color.rgb * 255.0 + 0.0001,0.0,255.0));
    if (cel_mode > 0.0) {
        float scale = page_index == 0 ? 255.0 : 128.0;
        vec3 base_light = cel_base_light;
        float luma = dot(base_light,vec3(.299,.587,.114));
        vec3 target = base_light * cel_darkness_multiplier;
        if (luma >= cel_thresholds.x) {
            vec3 hue = mix(vec3(1.0),base_light / max(luma,0.001),cel_hue_retention);
            if (luma < cel_thresholds.y) {
                target = hue * cel_shadow_tint * cel_levels.x;
            } else if (cel_three_tones && luma < cel_thresholds.z) {
                target = hue * cel_light_tint * cel_levels.y;
            } else {
                target = hue * cel_light_tint * cel_levels.z;
            }
        }
        float strength = cel_mode < 1.5 ? cel_strength.x : cel_strength.y;
        float depth = cel_orthographic_size > 0.0 ? -visibility_score : 1.0 / perspective_uvq.z;
        float fog = clamp((depth - cel_fog_range.x) * cel_fog_range.y,0.0,0.88);
        vec3 lit = mix(mix(base_light,target,strength),cel_fog_color,fog) * scale;
        vertex_rgb8 = floor(clamp(lit + cel_dynamic_light + 0.0001,0.0,255.0));
    }
    vec3 rgb8 = vertex_rgb8;
    if (page_index != 0) {
        int lookup_width = textureSize(texture_page_lookup,0).x;
        vec4 page = extended_texture_pages ? texelFetch(texture_page_lookup,ivec2(page_index % lookup_width,page_index / lookup_width),0) : texture_pages[page_index];
        // Integer texel addressing. Wrap within the logical page, never into its neighbour.
        vec2 sample_uv = UV;
        if (affine_texture_strength < 1.0) {
            vec2 perspective_uv = perspective_uvq.xy / max(perspective_uvq.z,0.00000001);
            sample_uv = mix(perspective_uv,UV,affine_texture_strength);
        }
        vec2 texel = mod(floor(sample_uv * page.zw + 0.00001),page.zw);
        vec2 atlas_uv = (page.xy + texel + vec2(0.5)) * TEXTURE_PIXEL_SIZE;
        vec4 sample_color = textureLod(TEXTURE,atlas_uv,0.0);
        if (sample_color.a < 0.5) { discard; }
        vec3 texel_rgb8 = floor(sample_color.rgb * 255.0 + 0.5);
        // Opaque PSX modulation: 0x80 is neutral, RGB555 texels expand with <<3.
        rgb8 = floor(texel_rgb8 * vertex_rgb8 / 128.0);
    }
    ivec2 pixel = ivec2(FRAGCOORD.xy * raster_pixel_scale);
#ifdef PSX_ADD_QUARTER
    float additive_coverage = 1.0;
#endif
    if (player_depth_correction && visibility_valid > 0.5) {
        vec2 visible = texelFetch(player_depth_texture,clamp(pixel,ivec2(0),ivec2(319,239)),0).rg;
        int coverage = int(visible.g + 0.5);
        bool ink = (packet_flags & 128) != 0;
        if (ink && (coverage & 2) != 0) { discard; }
        // One depth prepass covers the whole scene. PSX projection, affine UVs
        // and vertex colours keep their existing path.
        float tolerance = max(0.000001,abs(visible.r) * 0.00001);
        if ((world_depth_correction || ink || (packet_flags & 64) != 0 || (coverage & 1) != 0)) {
#ifdef PSX_ADD_QUARTER
            // Light shafts fade into the opaque surface they intersect.
            // A binary cut along the sheet would draw a dark triangular seam.
            float depth_delta = visibility_score - visible.r;
            if (depth_delta <= 0.0) { discard; }
            float contact_width = cel_orthographic_size > 0.0 ? 0.18 : max(0.00001,visible.r * visibility_score * 0.18);
            additive_coverage = smoothstep(0.0,contact_width,depth_delta);
#else
            if (visibility_score + tolerance < visible.r) { discard; }
#endif
        }
    }
    int matrix_index = (pixel.y & 3) * 4 + (pixel.x & 3);
    float offset = dither_enabled ? DITHER[matrix_index] : 0.0;
    vec3 rgb5 = floor(clamp(rgb8 + vec3(offset),0.0,255.0) / 8.0);
#ifdef PSX_ADD_QUARTER
    // ABR=3 adds the source's five-bit channels shifted right by two.
    COLOR = vec4(floor(floor(rgb5 / 4.0) * additive_coverage + 0.5) / 31.0,1.0);
#else
    bool translucent = (packet_flags & 32) != 0;
    float opacity = translucent ? flash_opacity : 1.0;
    if (mirror_enabled && visibility_valid > 0.5 && reflection_packet < -0.5) {
        vec2 mirror_uv = vec2(1.0 - FRAGCOORD.x / 320.0,FRAGCOORD.y / 240.0);
        vec3 reflected5 = floor(textureLod(mirror_texture,mirror_uv,0.0).rgb * 31.0 + 0.5);
        rgb5 = floor(mix(rgb5,reflected5,mirror_mix));
    }
    if (reflections_enabled && visibility_valid > 0.5 && abs(reflection_packet) >= 32.0) {
        float reflection_data = abs(reflection_packet);
        int packed_reflection = int(floor(reflection_data));
        int page_index_reflection = packed_reflection / 32;
        int light_index = packed_reflection % 32;
        float strength = max(0.0,(fract(reflection_data) - 0.125) * 4.0);
        int lookup_width = textureSize(texture_page_lookup,0).x;
        vec4 page = texelFetch(texture_page_lookup,ivec2(page_index_reflection % lookup_width,page_index_reflection / lookup_width),0);
        // Keep the painted band on the glass plane even across large,
        // foreshortened triangles. The pane's base UVs keep the PSX path.
        vec2 surface_uv = translucent ? reflection_uvq / perspective_uvq.z : reflection_uv;
        if (all(greaterThanEqual(surface_uv,vec2(0.0))) && all(lessThan(surface_uv,vec2(1.0)))) {
            vec2 texel = floor(surface_uv * page.zw + 0.00001);
            vec4 highlight = textureLod(TEXTURE,(page.xy + texel + vec2(0.5)) * TEXTURE_PIXEL_SIZE,0.0);
            vec3 lamp_tint = light_index == 0 ? vec3(1.0) : reflection_light_colors[light_index];
            vec3 reflected8 = highlight.rgb * 255.0 * lamp_tint;
            if (translucent && highlight.a > 0.0) {
                // Graded paint opacity sits over the transmitted glass color.
                float coverage = floor(clamp(highlight.a * strength * 0.42,0.0,0.45) * 31.0 + 0.5) / 31.0;
                if (coverage > 0.0) {
                    vec3 reflected5 = floor(clamp(reflected8 + vec3(offset),0.0,255.0) / 8.0);
                    float transmitted = opacity * (1.0 - coverage);
                    opacity = transmitted + coverage;
                    rgb5 = floor((rgb5 * transmitted + reflected5 * coverage) / opacity + 0.5);
                }
            } else if (!translucent && highlight.a >= 0.5) {
                vec3 front5 = floor(clamp(reflected8 * strength + vec3(offset),0.0,255.0) / 8.0);
                rgb5 = min(rgb5 + floor(front5 / 4.0),vec3(31.0));
            }
        }
    }
    COLOR = vec4(rgb5 / 31.0,opacity);
#endif
}
