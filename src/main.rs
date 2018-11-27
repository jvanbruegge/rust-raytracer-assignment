#[macro_use]
extern crate vulkano;
#[macro_use]
extern crate vulkano_shader_derive;
extern crate vulkano_win;
extern crate winit;

use vulkano_win::VkSurfaceBuild;

use vulkano::buffer::{BufferUsage, CpuAccessibleBuffer};
use vulkano::command_buffer::{AutoCommandBufferBuilder, DynamicState};
use vulkano::device::Device;
use vulkano::framebuffer::{Framebuffer, Subpass};
use vulkano::instance::Instance;
use vulkano::pipeline::viewport::Viewport;
use vulkano::pipeline::GraphicsPipeline;
use vulkano::swapchain;
use vulkano::swapchain::{
    AcquireError, PresentMode, SurfaceTransform, Swapchain, SwapchainCreationError,
};
use vulkano::sync::{now, GpuFuture};

use std::sync::Arc;
use std::time::SystemTime;

mod object;
mod shaders;

#[derive(Clone, Copy)]
#[allow(dead_code)]
struct PushData {
    time: f32,
    resolution: [u32; 2],
}

fn main() {
    let instance = {
        let extensions = vulkano_win::required_extensions();
        Instance::new(None, &extensions, None).expect("failed to create Vulkan instance")
    };

    let physical = vulkano::instance::PhysicalDevice::enumerate(&instance)
        .next()
        .expect("no device available");

    println!(
        "Using device: {} (type: {:?})",
        physical.name(),
        physical.ty()
    );

    let mut events_loop = winit::EventsLoop::new();
    let surface = winit::WindowBuilder::new()
        .build_vk_surface(&events_loop, instance.clone())
        .unwrap();

    let queue_family = physical
        .queue_families()
        .find(|&q| q.supports_graphics() && surface.is_supported(q).unwrap_or(false))
        .expect("couldn't find a graphical queue family");

    let (device, mut queues) = {
        let device_ext = vulkano::device::DeviceExtensions {
            khr_swapchain: true,
            ..vulkano::device::DeviceExtensions::none()
        };

        Device::new(
            physical,
            physical.supported_features(),
            &device_ext,
            [(queue_family, 0.5)].iter().cloned(),
        ).expect("failed to create device")
    };

    let queue = queues.next().unwrap();

    let mut dimensions; // viewport size can change

    let (mut swapchain, mut images) = {
        let caps = surface
            .capabilities(physical)
            .expect("failed to get surface capabilities");

        dimensions = caps.current_extent.unwrap_or([1024, 768]);
        let alpha = caps.supported_composite_alpha.iter().next().unwrap();
        let format = caps.supported_formats[0].0;

        Swapchain::new(
            device.clone(),
            surface.clone(),
            caps.min_image_count,
            format,
            dimensions,
            1,
            caps.supported_usage_flags,
            &queue,
            SurfaceTransform::Identity,
            alpha,
            PresentMode::Fifo,
            true,
            None,
        ).expect("failed to create swapchain")
    };

    let vertex_buffer = {
        #[derive(Debug, Clone)]
        struct Vertex {
            position: [f32; 2],
        }
        impl_vertex!(Vertex, position);

        CpuAccessibleBuffer::from_iter(
            device.clone(),
            BufferUsage::all(),
            [
                Vertex {
                    position: [-1.0, -1.0],
                },
                Vertex {
                    position: [1.0, -1.0],
                },
                Vertex {
                    position: [-1.0, 1.0],
                },
                Vertex {
                    position: [1.0, 1.0],
                },
                Vertex {
                    position: [1.0, -1.0],
                },
                Vertex {
                    position: [-1.0, 1.0],
                },
            ]
                .iter()
                .cloned(),
        ).expect("failed to create buffer")
    };

    let vs = shaders::get_vertex_shader(device.clone());
    let fs = shaders::get_fragment_shader(device.clone());

    let render_pass = Arc::new(
        single_pass_renderpass!(device.clone(),
        attachments: {
            color: { //color is a custom name here
                load: Clear,
                store: Store,
                format: swapchain.format(),
                samples: 1,
            }
        },
        pass: {
            color: [color], //here the name is referenced
            depth_stencil: {}
        }
    ).unwrap(),
    );

    let pipeline = Arc::new(
        GraphicsPipeline::start()
            .vertex_input_single_buffer()
            .vertex_shader(vs.main_entry_point(), ())
            .triangle_list()
            .viewports_dynamic_scissors_irrelevant(1)
            .fragment_shader(fs.main_entry_point(), ())
            .render_pass(Subpass::from(render_pass.clone(), 0).unwrap())
            .build(device.clone())
            .unwrap(),
    );

    let mut framebuffers: Option<Vec<Arc<vulkano::framebuffer::Framebuffer<_, _>>>> = None;

    let mut recreate_swapchain = false; //On window resize the swapchain has to be recreated

    let mut dynamic_state = DynamicState {
        line_width: None,
        viewports: Some(vec![Viewport {
            origin: [0.0, 0.0],
            dimensions: [dimensions[0] as f32, dimensions[1] as f32],
            depth_range: 0.0..1.0,
        }]),
        scissors: None,
    };

    let mut last_time = SystemTime::now();

    let _object = object::load_object("resources/bunny_low_res.ply");
    println!("Loaded model");

    let mut push_data = PushData {
        time: 0.0,
        resolution: dimensions,
    };

    let mut new_dimensions = dimensions;

    /*let (vertex_uniform, f1) = ImmutableBuffer::from_iter(
        object.vertices.into_iter(),
        BufferUsage {
            storage_buffer: true,
            ..BufferUsage::none()
        },
        queue.clone(),
    ).expect("Failed to create vertex uniform buffer");

    let (index_uniform, f2) = ImmutableBuffer::from_iter(
        object.indices.into_iter(),
        BufferUsage {
            storage_buffer: true,
            ..BufferUsage::none()
        },
        queue.clone(),
    ).expect("Failed to create index uniform buffer");*/

    /*let (bvh_uniform, f3) = ImmutableBuffer::from_iter(
        object.bvh.into_iter(),
        BufferUsage {
            storage_buffer: true,
            ..BufferUsage::none()
        },
        queue.clone(),
    ).expect("Failed to create bvh uniform buffer");*/

    let mut previous_frame_end = Box::new(
        now(device.clone())
            /*.join(f1)
            .join(f2)
            .join(f3)
            .then_signal_fence_and_flush()
            .unwrap(),*/
    ) as Box<GpuFuture>;

    /*let set = Arc::new(
        PersistentDescriptorSet::start(pipeline.clone(), 0)
            /*.add_buffer(vertex_uniform.clone())
            .unwrap()
            .add_buffer(index_uniform.clone())
            .unwrap()
            .add_buffer(bvh_uniform.clone())
            .unwrap()*/
            .build()
            .unwrap(),
    );*/

    loop {
        let current_time = SystemTime::now();
        let delta_time = current_time
            .duration_since(last_time)
            .unwrap()
            .subsec_nanos() as f32
            / 10.0e8;
        let new_time = push_data.time + delta_time;
        if new_time == push_data.time {
            push_data.time = 0.0;
        } else {
            push_data.time = new_time;
        }
        last_time = current_time;

        previous_frame_end.cleanup_finished();

        if recreate_swapchain {
            dimensions = surface
                .capabilities(physical)
                .expect("failed to get surface capabilities")
                .current_extent
                .unwrap();
        } else if dimensions != new_dimensions {
            recreate_swapchain = true;
            dimensions = new_dimensions;
        }
        if recreate_swapchain {
            println!("new size: {}, {}", dimensions[0], dimensions[1]);
            push_data.resolution = dimensions;

            let (new_swapchain, new_images) = match swapchain.recreate_with_dimension(dimensions) {
                Ok(r) => r,
                Err(SwapchainCreationError::UnsupportedDimensions) => {
                    continue;
                }
                Err(err) => panic!("{:?}", err),
            };

            swapchain = new_swapchain;
            images = new_images;

            framebuffers = None;

            dynamic_state.viewports = Some(vec![Viewport {
                origin: [0.0, 0.0],
                dimensions: [dimensions[0] as f32, dimensions[1] as f32],
                depth_range: 0.0..1.0,
            }]);

            recreate_swapchain = false;
        }

        if framebuffers.is_none() {
            framebuffers = Some(
                images
                    .iter()
                    .map(|image| {
                        Arc::new(
                            Framebuffer::start(render_pass.clone())
                                .add(image.clone())
                                .unwrap()
                                .build()
                                .unwrap(),
                        )
                    }).collect::<Vec<_>>(),
            );
        }

        let (image_num, acquire_future) =
            match swapchain::acquire_next_image(swapchain.clone(), None) {
                Ok(r) => r,
                Err(AcquireError::OutOfDate) => {
                    recreate_swapchain = true;
                    continue;
                }
                Err(err) => panic!("{:?}", err),
            };

        let command_buffer =
            AutoCommandBufferBuilder::primary_one_time_submit(device.clone(), queue.family())
                .unwrap()
                .begin_render_pass(
                    framebuffers.as_ref().unwrap()[image_num].clone(),
                    false,
                    vec![[0.0, 0.0, 1.0, 1.0].into()],
                ).unwrap()
                .draw(
                    pipeline.clone(),
                    &dynamic_state,
                    vertex_buffer.clone(),
                    (), //set.clone(),
                    push_data,
                ).unwrap()
                .end_render_pass()
                .unwrap()
                .build()
                .unwrap();

        let future = previous_frame_end
            .join(acquire_future)
            .then_execute(queue.clone(), command_buffer)
            .unwrap()
            .then_swapchain_present(queue.clone(), swapchain.clone(), image_num)
            .then_signal_fence_and_flush();

        match future {
            Ok(future) => {
                previous_frame_end = Box::new(future) as Box<_>;
            }
            Err(vulkano::sync::FlushError::OutOfDate) => {
                recreate_swapchain = true;
                previous_frame_end = Box::new(vulkano::sync::now(device.clone())) as Box<_>;
            }
            Err(e) => {
                println!("{:?}", e);
                previous_frame_end = Box::new(vulkano::sync::now(device.clone())) as Box<_>;
            }
        }

        let mut done = false;
        events_loop.poll_events(|ev| match ev {
            winit::Event::WindowEvent {
                event: winit::WindowEvent::CloseRequested,
                ..
            } => done = true,
            winit::Event::WindowEvent {
                event: winit::WindowEvent::Resized(size),
                ..
            } => {
                let (w, h): (u32, u32) = size.into();
                new_dimensions = [w, h];
            }
            _ => (),
        });
        if done {
            return;
        }
    }
}
