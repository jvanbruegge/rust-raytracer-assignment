// Tampere University of Technology
// TIE-52306 Computer Graphics Coding Assignment 2018
//
// Write your name and student id here:
//   Jan van Brügge, 282922
// Mark here with an X what functionalities you implemented
// Note that different functionalities are worth different amount of points.
//
// Name of the functionality      |Done| Notes
//-------------------------------------------------------------------------------
// example functionality          | X  | Example note: control this with var YYYY
// Madatory functionalities -----------------------------------------------------
//   Perspective projection       | X  | 
//   Phong shading                | X  | 
//   Camera movement and rotation | X  | 
// Extra funtionalities ---------------------------------------------------------
//   Attend visiting lecture 1    |    | 
//   Attend visiting lecture 2    |    | 
//   Tone mapping                 |    | 
//   PBR shading                  |    | 
//   Sharp shadows                |    | 
//   Soft shadows                 |    | 
//   Sharp reflections            |    | 
//   Glossy refelctions           |    | 
//   Refractions                  |    | 
//   Caustics                     |    | 
//   Texturing                    |    | 
//   Simple game                  |    | 
//   Progressive path tracing     |    | 
//   Basic post-processing        |    | 
//   Advanced post-processing     |    | 
//   Simple own SDF               |    | 
//   Advanced own SDF             |    | 
//   Animated SDF                 |    | 
//   Other?                       |    | 
//   Ray-Triangle Intersection    | X  |
//   BVH tree generation          | X  |
//   Custom loader                | X  |

#version 450

const float PI = 3.1415926535897932384626433832795;
const float EPSILON = 0.00001;
const float INFINITY = 1.0 / 0.0;
const uint UINT_MAX = 0xFFFF;

// These definitions are tweakable.

/* Minimum distance a ray must travel. Raising this value yields some performance
 * benefits for secondary rays at the cost of weird artefacts around object
 * edges.
 */
#define MIN_DIST 0.08
/* Maximum distance a ray can travel. Changing it has little to no performance
 * benefit for indoor scenes, but useful when there is nothing for the ray
 * to intersect with (such as the sky in outdoors scenes).
 */
#define MAX_DIST 20.0
/* Maximum number of steps the ray can march. High values make the image more
 * correct around object edges at the cost of performance, lower values cause
 * weird black hole-ish bending artefacts but is faster.
 */
#define MARCH_MAX_STEPS 128
/* Typically, this doesn't have to be changed. Lower values cause worse
 * performance, but make the tracing stabler around slightly incorrect distance
 * functions.
 * The current value merely helps with rounding errors.
 */
#define STEP_RATIO 0.999
/* Determines what distance is considered close enough to count as an
 * intersection. Lower values are more correct but require more steps to reach
 * the surface
 */
#define HIT_RATIO 0.001

// Mouse coordinates
//uniform vec2 u_mouse;

layout(push_constant) uniform PushData {
    float time;
    uint width;
    uint height;
    uint vert_length;
    uint idx_length;
} push_data;

layout(location = 0) out vec4 f_color;

layout(set = 0, binding = 0) buffer VertexData {
    vec3[] vertices;
} vert;

layout(set = 0, binding = 1) buffer IndexData {
    uvec3[] indices;
} idx;

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

layout(set = 0, binding = 2) buffer BVH {
    Node[] nodes;
} bvh;

struct material
{
    // The color of the surface
    vec4 color;
    // You can add your own material features here!
};

// Good resource for finding more building blocks for distance functions:
// http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm

/* Basic box distance field.
 *
 * Parameters:
 *  p   Point for which to evaluate the distance field
 *  b   "Radius" of the box
 *
 * Returns:
 *  Distance to the box from point p.
 */
float box(vec3 p, vec3 b)
{
    vec3 d = abs(p) - b;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

/* Rotates point around origin along the X axis.
 *
 * Parameters:
 *  p   The point to rotate
 *  a   The angle in radians
 *
 * Returns:
 *  The rotated point.
 */
vec3 rot_x(vec3 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return vec3(
        p.x,
        c*p.y-s*p.z,
        s*p.y+c*p.z
    );
}

/* Rotates point around origin along the Y axis.
 *
 * Parameters:
 *  p   The point to rotate
 *  a   The angle in radians
 *
 * Returns:
 *  The rotated point.
 */
vec3 rot_y(vec3 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return vec3(
        c*p.x+s*p.z,
        p.y,
        -s*p.x+c*p.z
    );
}

/* Rotates point around origin along the Z axis.
 *
 * Parameters:
 *  p   The point to rotate
 *  a   The angle in radians
 *
 * Returns:
 *  The rotated point.
 */
vec3 rot_z(vec3 p, float a)
{
    float s = sin(a);
    float c = cos(a);
    return vec3(
        c*p.x-s*p.y,
        s*p.x+c*p.y,
        p.z
    );
}

/* Each object has a distance function and a material function. The distance
 * function evaluates the distance field of the object at a given point, and
 * the material function determines the surface material at a point.
 */

float blob_distance(vec3 p)
{
    vec3 q = p - vec3(-0.5, -2.2 + abs(sin(push_data.time*3.0)), 2.0);
    return length(q) - 0.8 + sin(10.0*q.x)*sin(10.0*q.y)*sin(10.0*q.z)*0.07;
}

material blob_material(vec3 p)
{
    material mat;
    mat.color = vec4(1.0, 0.5, 0.3, 0.0);
    return mat;
}

float sphere_distance(vec3 p)
{
    return length(p - vec3(1.5, -1.8, 4.0)) - 1.2;
}

material sphere_material(vec3 p)
{
    material mat;
    mat.color = vec4(0.1, 0.2, 0.0, 1.0);
    return mat;
}

float room_distance(vec3 p)
{
    return max(
        -box(p-vec3(0.0,3.0,3.0), vec3(0.5, 0.5, 0.5)),
        -box(p-vec3(0.0,0.0,0.0), vec3(3.0, 3.0, 6.0))
    );
}

material room_material(vec3 p)
{
    material mat;
    mat.color = vec4(1.0, 1.0, 1.0, 1.0);
    if(p.x <= -2.98) mat.color.rgb = vec3(1.0, 0.0, 0.0);
    else if(p.x >= 2.98) mat.color.rgb = vec3(0.0, 1.0, 0.0);
    return mat;
}

float crate_distance(vec3 p)
{
    return box(rot_y(p-vec3(-1,-1,5), push_data.time), vec3(1, 2, 1));
}

material crate_material(vec3 p)
{
    material mat;
    mat.color = vec4(1.0, 1.0, 1.0, 1.0);

    vec3 q = rot_y(p-vec3(-1,-1,5), push_data.time) * 0.98;
    if(fract(q.x + floor(q.y*2.0) * 0.5 + floor(q.z*2.0) * 0.5) < 0.5)
    {
        mat.color.rgb = vec3(0.0, 1.0, 1.0);
    }
    return mat;
}

/* The distance function collecting all others.
 *
 * Parameters:
 *  p   The point for which to find the nearest surface
 *  mat The material of the nearest surface
 *
 * Returns:
 *  The distance to the nearest surface.
 */
float map(
    in vec3 p,
    out material mat
){
    float min_dist = MAX_DIST*2.0;
    float dist = 0.0;

    dist = blob_distance(p);
    if(dist < min_dist) {
        mat = blob_material(p);
        min_dist = dist;
    }

    dist = room_distance(p);
    if(dist < min_dist) {
        mat = room_material(p);
        min_dist = dist;
    }

    dist = crate_distance(p);
    if(dist < min_dist) {
        mat = crate_material(p);
        min_dist = dist;
    }

    dist = sphere_distance(p);
    if(dist < min_dist) {
        mat = sphere_material(p);
        min_dist = dist;
    }

    // Add your own objects here!

    return min_dist;
}

/* Calculates the normal of the surface closest to point p.
 *
 * Parameters:
 *  p   The point where the normal should be calculated
 *  mat The material information, produced as a byproduct
 *
 * Returns:
 *  The normal of the surface.
 *
 * See http://www.iquilezles.org/www/articles/normalsSDF/normalsSDF.htm if
 * you're interested in how this works.
 */
vec3 normal(vec3 p, out material mat)
{
    const vec2 k = vec2(1.0, -1.0);
    return normalize(
        k.xyy * map(p + k.xyy * EPSILON, mat) +
        k.yyx * map(p + k.yyx * EPSILON, mat) +
        k.yxy * map(p + k.yxy * EPSILON, mat) +
        k.xxx * map(p + k.xxx * EPSILON, mat)
    );
}

// Möller-Trumbore algorithm, from Wikipedia
bool testIntersection(in Ray r, in vec3 camera_pos, in vec3 v0, in vec3 v1, in vec3 v2, out vec3 intersection, out float dist) {
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

/* Finds the closest intersection of the ray with the scene.
 *
 * Parameters:
 *  o           Origin of the ray
 *  v           Direction of the ray
 *  max_dist    Maximum distance the ray can travel. Usually MAX_DIST.
 *  p           Location of the intersection
 *  n           Normal of the surface at the intersection point
 *  mat         Material of the intersected surface
 *  inside      Whether we are marching inside an object or not. Useful for
 *              refractions.
 *
 * Returns:
 *  true if a surface was hit, false otherwise.
 */
bool intersect(
    in vec3 o,
    in vec3 v,
    in float max_dist,
    out vec3 p,
    out vec3 n,
    out material mat,
    bool inside
) {
    float t = MIN_DIST;
    float dir = inside ? -1.0 : 1.0;
    bool hit = false;
    Ray ray;
    ray.orig = o;
    ray.dir = v;
    ray.dir_inv = 1/v;
    uint current = bvh.nodes.length() - 1;

    if(testBox(ray, current)) {
        while((current = getNextNode(current, ray)) < UINT_MAX) {
            if(isLeaf(current)) {
                uvec3 idx = getIndices(current);
                vec3 v0 = vert.vertices[idx.x];
                vec3 v1 = vert.vertices[idx.y];
                vec3 v2 = vert.vertices[idx.z];
                float t;
                float dist;

                if(testIntersection(ray, o, v0, v1, v2, p, t)) {
                    hit = true;
                    if(t < dist) {
                        dist = t;
                        n = normalize(cross(v1 - v0, v2 - v0));
                        material m;
                        m.color = vec4(0, 0, 0.5, 1.0);
                        mat = m;
                    }
                }
            }
        }
    }

    if(!hit) {
        for(int i = 0; i < MARCH_MAX_STEPS; ++i)
        {
            p = o + t * v;
            float dist = dir * map(p, mat);

            hit = abs(dist) < HIT_RATIO * t;

            if(hit || t > max_dist) break;

            t += dist * STEP_RATIO;
        }

        n = normal(p, mat);
    }

    return hit;
}

/* Calculates the color of the pixel, based on view ray origin and direction.
 *
 * Parameters:
 *  o   Origin of the view ray
 *  v   Direction of the view ray
 *
 * Returns:
 *  Color of the pixel.
 */
vec3 render(vec3 o, vec3 v)
{
    // This lamp is positioned at the hole in the roof.
    vec3 lamp_pos = vec3(0.0, 3.1, 3.0);

    vec3 p, n;
    material mat;

    // Compute intersection point along the view ray.
    intersect(o, v, MAX_DIST, p, n, mat, false);

    // Add some lighting code here!
    vec3 light_dir = normalize(lamp_pos - p);
    float l = max(dot(light_dir, n), 0.0);
    float s = 0.0;

    if(l > 0.0) {
        vec3 refl_dir = reflect(-light_dir, n);
        float angle = max(dot(refl_dir, v), 0.0);
        s = pow(angle, 4.0);
    }

    return l * mat.color.rgb + s * vec3(1.0);
}

const float near_plane = 0.01;
const float FOV = radians(90);

void getEdges(in vec3 camera_pos, in vec3 camera_dir,
        out vec3 upper_left, out vec3 upper_right, out vec3 lower_left) {

    vec3 camera_up = vec3(0.0, 1.0, 0.0);
    vec3 camera_right = cross(camera_dir, camera_up);
    float plane_x_half = sin(FOV/2) * near_plane;
    float plane_y_half = plane_x_half * push_data.height / push_data.width;

    vec3 x = camera_right * plane_x_half;
    vec3 y = camera_up * plane_y_half;
    vec3 z = camera_dir * near_plane;

    upper_left = camera_pos - x + y + z;
    upper_right = camera_pos + x + y + z;
    lower_left = camera_pos - x - y + z;
}

vec3 getRay(in vec3 camera_pos, in vec3 camera_dir) {
    vec3 u_l, u_r, l_l;
    getEdges(camera_pos, camera_dir, u_l, u_r, l_l);

    return normalize(
        (u_l + (gl_FragCoord.x / push_data.width) * (u_r - u_l)
            + (gl_FragCoord.y / push_data.height) * (l_l - u_l))
        - camera_pos
    );
}

void main()
{
    vec2 u_resolution = vec2(push_data.width, push_data.height);
    // This is the position of the pixel in normalized device coordinates.
    vec2 uv = (gl_FragCoord.xy/u_resolution)*2.0-1.0;
    //hack to flip image
    uv = vec2(uv.x, -uv.y);
    // Calculate aspect ratio
    float aspect = u_resolution.x/u_resolution.y;

    // Modify these two to create perspective projection!
    // Origin of the view ray
    vec3 o = vec3(0.0, sin(push_data.time), -5.0);

    vec3 dir = normalize(vec3(sin(push_data.time)*0.1, 0, 1 + cos(push_data.time)*0.1));

    // Direction of the view ray
    vec3 v = getRay(o, dir);

    f_color = vec4(render(o, v), 1.0);
}
