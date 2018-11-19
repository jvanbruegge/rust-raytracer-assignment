#version 450

const float PI = 3.1415926535897932384626433832795;
const float EPSILON = 0.0000001;
const float INFINITY = 1.0 / 0.0;
const uint UINT_MAX = 0xFFFF;

layout(location = 0) out vec4 f_color;

struct Node {
    float[6] bounding_box;
    uint left_child;
    uint right_child;
    uint parent;
    uint is_leaf;
};

struct Ray {
    vec3 orig;
    vec3 dir;
    vec3 dir_inv;
};

// Has to be 128 bytes max, and divible by 4
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

layout(set = 0, binding = 2) buffer BVH {
    Node[] nodes;
} bvh;

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
bool testIntersection(in Ray r, in vec3 v0, in vec3 v1, in vec3 v2, out vec3 intersection, out float dist) {
    vec3 ray = r.dir;
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
        dist = t;
        return true;
    }
    return false;
}

bool testBox(in Ray r, in uint node) {
    float[6] aabb = bvh.nodes[node].bounding_box;
    double t1 = (aabb[0] - r.orig.x) * r.dir_inv.x;
    double t2 = (aabb[1] - r.orig.x) * r.dir_inv.x;

    double tmin = min(t1, t2);
    double tmax = max(t1, t2);

    t1 = (aabb[2] - r.orig.y) * r.dir_inv.y;
    t2 = (aabb[3] - r.orig.y) * r.dir_inv.y;
    tmin = max(tmin, min(t1, t2));
    tmax = min(tmax, max(t1, t2));

    t1 = (aabb[4] - r.orig.z) * r.dir_inv.z;
    t2 = (aabb[5] - r.orig.z) * r.dir_inv.z;
    tmin = max(tmin, min(t1, t2));
    tmax = min(tmax, max(t1, t2));

    return tmax > max(tmin, 0.0);
}

uvec3 getIndices(uint node) {
    Node n = bvh.nodes[node];
    return uvec3(
        floatBitsToUint(n.bounding_box[0]),
        floatBitsToUint(n.bounding_box[1]),
        floatBitsToUint(n.bounding_box[2])
    );
}

bool isLeaf(uint node) {
    return bvh.nodes[node].is_leaf == 1;
}

uint getNextNode(uint node, Ray ray) {
    if(!isLeaf(node) && testBox(ray, node)) {
        return bvh.nodes[node].left_child;
    }

    uint root = bvh.nodes.length() - 1;
    uint ni = node;
    while(ni < root) {
        Node n = bvh.nodes[ni];
        Node parent = bvh.nodes[n.parent];
        if(ni == parent.left_child && testBox(ray, parent.right_child)) {
            return parent.right_child;
        }
        ni = n.parent;
    }
    return UINT_MAX;
}

void main() {
    vec3 ray_dir = getRay();
    Ray ray = Ray(camera_pos, ray_dir, 1 / ray_dir);

    bool hit = false;
    vec3 normal;

    uint root = bvh.nodes.length() - 1;
    if(testBox(ray, root)) {
        uint current = root;
        float dist = INFINITY;

        while((current = getNextNode(current, ray)) < UINT_MAX) {
            if(isLeaf(current)) {
                uvec3 idx = getIndices(current);
                vec3 v0 = vert.vertices[idx.x];
                vec3 v1 = vert.vertices[idx.y];
                vec3 v2 = vert.vertices[idx.z];
                vec3 tmp;
                float t;

                if(testIntersection(ray, v0, v1, v2, tmp, t)) {
                    hit = true;
                    if(t < dist) {
                        dist = t;
                        normal = normalize(cross(v1 - v0, v2 - v0));
                    }
                }
            }
        }
    }

    if(hit) {
        f_color = vec4(normal, 1.0);
    } else {
        f_color = vec4(0.0);
    }
}
