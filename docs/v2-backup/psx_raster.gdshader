shader_type canvas_item;
render_mode unshaded;
uniform bool dither_enabled = true;
varying vec4 modulation;
const float DITHER[16] = float[16](
    -4.0, 0.0,-3.0, 1.0,
     2.0,-2.0, 3.0,-1.0,
    -3.0, 1.0,-4.0, 0.0,
     3.0,-1.0, 2.0,-2.0
);
void vertex() {
    modulation = COLOR;
}
void fragment() {
    // PSX texture texels are RGB555; neutral modulation is the integer 128.
    vec3 texel8 = floor(texture(TEXTURE, UV).rgb * 255.0 / 8.0) * 8.0;
    vec3 rgb8 = floor(texel8 * modulation.rgb);
    ivec2 pixel = ivec2(FRAGCOORD.xy);
    int row = pixel.y & 3;
    int index = row * 4 + (pixel.x & 3);
    float offset = dither_enabled ? DITHER[index] : 0.0;
    vec3 rgb5 = floor(clamp(rgb8 + vec3(offset),0.0,255.0) / 8.0);
    COLOR = vec4(rgb5 / 31.0,1.0);
}
