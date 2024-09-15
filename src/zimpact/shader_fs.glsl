#version 140
in vec4 v_color;
in vec2 v_uv;
out vec4 fragment_color_output;
uniform sampler2D u_texture;

void main(void) {
	vec4 tex_color = texture(u_texture, v_uv);
	vec4 color = tex_color * v_color;
	fragment_color_output = color;
}