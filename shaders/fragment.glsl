#version 450

const float PI = 3.1415926535897932384626433832795;
const float EPSILON = 0.0000001;

layout(location = 0) out vec4 f_color;

// Has to be 128 bytes max, and divible by 4
// Currently 4 + 8 = 20 bytes used
layout(push_constant) uniform PushData {
    float time;
    uint width;
    uint height;
} push_data;

layout(set = 0, binding = 0) buffer VertexData {
    vec3[] vertices;
} vert;

layout(set = 0, binding = 1) buffer IndexData {
    uvec3[] indices;
} idx;

const vec3 camera_pos = vec3(0, 0.1, -0.5);
const float near_plane = 0.5;
const float FOV = radians(49.1);

const float plane_x_half = sin(FOV/2) * near_plane;

void getEdges(out vec3 upper_left, out vec3 upper_right, out vec3 lower_left) {
    float plane_y_half = plane_x_half * push_data.height / push_data.width;

    upper_left = camera_pos + vec3(-plane_x_half, plane_y_half, near_plane);
    upper_right = camera_pos + vec3(plane_x_half, plane_y_half, near_plane);
    lower_left = camera_pos + vec3(-plane_x_half, -plane_y_half, near_plane);
}

vec3 getRay() {
    vec3 u_l, u_r, l_l;
    getEdges(u_l, u_r, l_l);

    return normalize(
        (u_l + (gl_FragCoord.x / push_data.width) * (u_r - u_l)
            + (gl_FragCoord.y / push_data.height) * (l_l - u_l))
        - camera_pos
    );
}

// Möller-Trumbore algorithm, from Wikipedia
bool testIntersection(in vec3 ray, in vec3 v0, in vec3 v1, in vec3 v2, out vec3 intersection) {
    vec3 edge1 = v1 - v0;
    vec3 edge2 = v2 - v0;
    vec3 h = cross(ray, edge2);
    float a = dot(edge1, h);
    if(a > -EPSILON && a < EPSILON) return false; // parallel ray

    float f = 1.0 / a;
    vec3 s = camera_pos - v0;
    float u = f * dot(s, h);
    if(u < 0.0 || u > 1.0) return false;

    vec3 q = cross(s, edge1);
    float v = f * dot(ray, q);
    if(v < 0.0 || u + v > 1.0) return false;

    float t = f * dot(edge2, q);
    if(t > EPSILON) {
        intersection = camera_pos + ray * t;
        return true;
    }
    return false;
}

void main() {
    vec3 ray = getRay();
    bool hit = false;
    vec3 normal;
    vec3 tmp;

    for(uint i = 0; i < idx.indices.length(); i++) {
        uvec3 n = idx.indices[i];
        vec3 v0 = vert.vertices[n.x];
        vec3 v1 = vert.vertices[n.y];
        vec3 v2 = vert.vertices[n.z];

        if(testIntersection(ray, v0, v1, v2, tmp)) {
            hit = true;
            normal = normalize(cross(v1 - v0, v2 - v0));
            break;
        }
    }

    if(hit) {
        f_color = vec4(normal, 1.0);
    } else {
        f_color = vec4(0.0);
    }
}
