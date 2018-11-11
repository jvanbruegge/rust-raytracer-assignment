#version 450

#define PI 3.1415926535897932384626433832795

layout(location = 0) out vec4 f_color;

// Has to be 128 bytes max, and divible by 4
// Currently 4 + 8 + 8 = 20 bytes used
layout(push_constant) uniform PushData {
    float time;
    uint width;
    uint height;
    uint vert_length;
    uint idx_length;
} push_data;

layout(set = 0, binding = 0) uniform VertexData {
    vec3[] vertices;
} vert;

layout(set = 0, binding = 1) uniform IndexData {
    uvec3[] indices;
} idx;

void main() {
    f_color = vec4(
        gl_FragCoord.x / push_data.width,
        gl_FragCoord.y / push_data.height,
        0.0,
        1.0
    );
}
