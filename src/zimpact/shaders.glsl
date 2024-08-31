@vs vs
uniform vs_params {
    vec2 screen;
};

in vec2 position;
in vec2 texcoord0;
in vec4 color0;
out vec2 uv;
out vec4 color;
void main() {
    gl_Position = vec4(
			floor(position + 0.5) * (vec2(2,-2)/screen.xy) + vec2(-1.0,1.0),
			0.0, 1.0
		);
    uv = texcoord0;
    color = color0;
}
@end

@fs fs
uniform texture2D tex;
uniform sampler smp;
in vec2 uv;
in vec4 color;
out vec4 frag_color;
void main() {
    frag_color = texture(sampler2D(tex, smp), uv.xy) * color;
}
@end

@program sgl vs fs