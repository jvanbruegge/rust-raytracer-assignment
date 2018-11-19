mod bvh;
mod object_loader;

pub struct Object {
    pub vertices: Vec<[f32; 4]>,
    pub indices: Vec<[u32; 4]>,
    pub bvh: Vec<bvh::Node>,
}

pub fn load_object(path: &str) -> Object {
    let (vertices, indices) = object_loader::load_model(path);

    let bvh = bvh::construct_bvh(&vertices, &indices);

    Object {
        vertices,
        indices,
        bvh,
    }
}
