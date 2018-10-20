#version 450

#define PI 3.1415926535897932384626433832795

layout(location = 0) out vec4 f_color;

layout(push_constant) uniform Data {
    float timer;
} data;

void main() {
    const float inner_timer = data.timer;
    f_color = vec4(
        sin(inner_timer),
        sin(inner_timer * PI / 3),
        sin(inner_timer * PI / 3 * 2),
        1.0
    );
}

