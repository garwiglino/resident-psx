shader_type canvas_item;
render_mode unshaded;
uniform vec4 outline_color : source_color = vec4(0.87,0.84,0.67,1.0);
void fragment() {
    vec2 p = TEXTURE_PIXEL_SIZE;
    float a = texture(TEXTURE,UV).a;
    float rim = max(max(texture(TEXTURE,UV+vec2(p.x,0)).a,texture(TEXTURE,UV-vec2(p.x,0)).a),
                    max(texture(TEXTURE,UV+vec2(0,p.y)).a,texture(TEXTURE,UV-vec2(0,p.y)).a));
    COLOR = vec4(floor(outline_color.rgb*31.0+0.5)/31.0,outline_color.a*step(0.5,rim)*(1.0-step(0.5,a)));
}
