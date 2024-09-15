#version 140
in vec4 pos;
in vec2 uv;
in vec4 color;
out vec4 v_color;
out vec2 v_uv;

uniform vec2 screen;

void main(void) {
	v_color = color;
	v_uv = uv;
	gl_Position = vec4(
		floor(pos.xy + 0.5) * (vec2(2,-2)/screen.xy) + vec2(-1.0,1.0),
		0.0, 1.0
	);
}