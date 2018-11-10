#version 450

#define PI 3.1415926535897932384626433832795

layout(location = 0) out vec4 f_color;

// Has to be 128 bytes max, and divible by 4
// Currently 4 + 8 = 12 bytes used
layout(push_constant) uniform PushData {
    float time;
    uvec2 resolution;
} push_data;

void main() {
    const float t = push_data.resolution.x / 400.0;
    f_color = vec4(
        sin(t),
        sin(t * PI / 3),
        sin(t * PI / 3 * 2),
        1.0
    );
}

