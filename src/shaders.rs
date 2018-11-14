use std::sync::Arc;
use vulkano::device::Device;

mod vs {
    #[derive(VulkanoShader)]
    #[ty = "vertex"]
    #[src = "
#version 450

layout(location = 0) in vec2 position;

void main() {
    gl_Position = vec4(position, 0.0, 1.0);
}
"]
    #[allow(dead_code)]
    struct Dummy;
}

#[allow(dead_code)] // Used to force recompilation of shader change
const X: &str = include_str!("../shaders/fragment.glsl");
#[allow(dead_code)] // Used to force recompilation of shader change
const X1: &str = include_str!("../shaders/example.glsl");

mod fs {
    #[derive(VulkanoShader)]
    #[ty = "fragment"]
    #[path = "shaders/fragment.glsl"]
    //#[path = "shaders/example.glsl"]
    #[allow(dead_code)]
    struct Dummy;
}

pub fn get_fragment_shader(device: Arc<Device>) -> fs::Shader {
    fs::Shader::load(device).expect("failed to create shader module")
}

pub fn get_vertex_shader(device: Arc<Device>) -> vs::Shader {
    vs::Shader::load(device).expect("failed to create shader module")
}
