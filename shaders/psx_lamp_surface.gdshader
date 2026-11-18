shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool has_texture = false;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec3 emission_color = vec3(0.0);
uniform float alpha_scissor_threshold = 0.5;
instance uniform vec4 psx_lamp_color : source_color, instance_index(0) = vec4(1.0);
void fragment() {
    vec4 texel = has_texture ? texture(albedo_texture,UV) : vec4(1.0);
    if (texel.a * tint.a < alpha_scissor_threshold) { discard; }
    ALBEDO = texel.rgb * tint.rgb * psx_lamp_color.rgb;
}
