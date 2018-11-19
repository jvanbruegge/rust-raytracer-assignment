#[derive(PartialEq, Eq, PartialOrd, Ord, Clone, Copy)]
struct Morton(u32);

use std::f32::{INFINITY, NEG_INFINITY};
use std::iter::FromIterator;
use std::num::Wrapping;
use std::ops::BitXor;

impl BitXor for Morton {
    type Output = Self;

    fn bitxor(self, rhs: Self) -> Self {
        Morton(self.0 ^ rhs.0)
    }
}

impl Morton {
    fn leading_zeros(&self) -> u32 {
        self.0.leading_zeros()
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct InnerNodeData {
    bounding_box: [f32; 6],
    left_child: u32,
    right_child: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union NodeData {
    leaf: [u32; 4],
    node: InnerNodeData,
}

#[repr(C)]
#[allow(dead_code)]
#[derive(Clone)]
pub struct Node {
    data: NodeData,
    parent: u32,
    is_leaf: bool,
}

fn expand_bits(v: u32) -> u32 {
    let mut x = (Wrapping(v) * Wrapping(0x00010001u32)) & Wrapping(0xFF0000FFu32);
    x = (x * Wrapping(0x00000101u32)) & Wrapping(0x0F00F00Fu32);
    x = (x * Wrapping(0x00000011u32)) & Wrapping(0xC30C30C3u32);

    x = (x * Wrapping(0x00000005u32)) & Wrapping(0x49249249u32);

    x.0
}

/**
 * Calculates a 30-bit Morton code for a point in the unit cube
 */
fn morton_3d([x, y, z]: [f32; 3]) -> Morton {
    let u = (x * 1024.0).max(0.0).min(1023.0);
    let v = (y * 1024.0).max(0.0).min(1023.0);
    let w = (z * 1024.0).max(0.0).min(1023.0);

    let xx = expand_bits(u as u32);
    let yy = expand_bits(v as u32);
    let zz = expand_bits(w as u32);

    Morton(xx * 4 + yy * 2 + zz)
}

enum BVH {
    Leaf([u32; 4]),
    Node(Box<BVH>, Box<BVH>),
}

// uses LBVH algorithm
pub fn construct_bvh(vertices: &Vec<[f32; 4]>, indices: &Vec<[u32; 4]>) -> Vec<Node> {
    let (xmin, xmax, ymin, ymax, zmin, zmax) = (&vertices).into_iter().fold(
        (
            INFINITY,
            NEG_INFINITY,
            INFINITY,
            NEG_INFINITY,
            INFINITY,
            NEG_INFINITY,
        ),
        |(x0, x1, y0, y1, z0, z1), [x, y, z, _]| {
            (
                x0.min(*x),
                x1.max(*x),
                y0.min(*y),
                y1.max(*y),
                z0.min(*z),
                z1.max(*z),
            )
        },
    );

    let (x_length, y_length, z_length) = (xmax - xmin, ymax - ymin, zmax - zmin);

    let centers = indices.into_iter().map(|[x, y, z, _]| {
        let i = *x as usize;
        let j = *y as usize;
        let k = *z as usize;
        let xm = vertices[i][0].min(vertices[j][0]).min(vertices[k][0]);
        let ym = vertices[i][1].min(vertices[j][1]).min(vertices[k][1]);
        let zm = vertices[i][2].min(vertices[j][2]).min(vertices[k][2]);

        let xx = vertices[i][0].max(vertices[j][0]).max(vertices[k][0]);
        let yy = vertices[i][1].max(vertices[j][1]).max(vertices[k][1]);
        let zz = vertices[i][2].max(vertices[j][2]).max(vertices[k][2]);

        [(xm + xx) / 2.0, (ym + yy) / 2.0, (zm + zz) / 2.0]
    });

    let mut morton_codes = Vec::from_iter(
        centers
            .map(|[x, y, z]| {
                [
                    (x - xmin) / x_length,
                    (y - ymin) / y_length,
                    (z - zmin) / z_length,
                ]
            }).map(morton_3d),
    );
    let morton_slice = &mut morton_codes[..];
    morton_slice.sort_unstable();

    let tree = generate_hierarchy(morton_slice, indices, 0, morton_slice.len() - 1);

    let mut flat_tree: Vec<Node> = Vec::new();
    flat_tree.reserve_exact(indices.len() * 2 - 1);

    flatten_tree(&mut flat_tree, &tree, vertices);
    let idx = flat_tree.len() - 1 as usize;

    set_parents(&mut flat_tree, idx);

    flat_tree
}

fn set_parents(vec: &mut Vec<Node>, index: usize) {
    let (l, r) = unsafe {
        let n = &vec[index];
        (
            n.data.node.left_child as usize,
            n.data.node.right_child as usize,
        )
    };

    vec[l].parent = index as u32;
    vec[r].parent = index as u32;

    if !vec[l].is_leaf {
        set_parents(vec, l);
    }
    if !vec[r].is_leaf {
        set_parents(vec, r);
    }
}

fn flatten_tree(vec: &mut Vec<Node>, tree: &BVH, vertices: &Vec<[f32; 4]>) -> usize {
    match tree {
        BVH::Leaf(idx) => {
            vec.push(Node {
                is_leaf: true,
                parent: 0,
                data: NodeData { leaf: *idx },
            });

            vec.len() - 1
        }
        BVH::Node(l, r) => {
            let left_idx = flatten_tree(vec, l, vertices);
            let right_idx = flatten_tree(vec, r, vertices);

            let lbb = unsafe {
                if vec[left_idx].is_leaf {
                    calc_leaf_bb(&vec[left_idx].data.leaf, vertices)
                } else {
                    vec[left_idx].data.node.bounding_box
                }
            };
            let rbb = unsafe {
                if vec[right_idx].is_leaf {
                    calc_leaf_bb(&vec[right_idx].data.leaf, vertices)
                } else {
                    vec[right_idx].data.node.bounding_box
                }
            };

            vec.push(Node {
                is_leaf: false,
                parent: 0,
                data: NodeData {
                    node: InnerNodeData {
                        left_child: left_idx as u32,
                        right_child: right_idx as u32,
                        bounding_box: [
                            lbb[0].min(rbb[0]),
                            lbb[1].max(rbb[1]),
                            lbb[2].min(rbb[2]),
                            lbb[3].max(rbb[3]),
                            lbb[4].min(rbb[4]),
                            lbb[5].max(rbb[5]),
                        ],
                    },
                },
            });

            vec.len() - 1
        }
    }
}

fn calc_leaf_bb(idx: &[u32; 4], vertices: &Vec<[f32; 4]>) -> [f32; 6] {
    let v0 = vertices[idx[0] as usize];
    let v1 = vertices[idx[1] as usize];
    let v2 = vertices[idx[2] as usize];

    [
        v0[0].min(v1[0]).min(v2[0]),
        v0[0].max(v1[0]).max(v2[0]),
        v0[1].min(v1[1]).min(v2[1]),
        v0[1].max(v1[1]).max(v2[1]),
        v0[2].min(v1[2]).min(v2[2]),
        v0[2].max(v1[2]).max(v2[2]),
    ]
}

fn generate_hierarchy(
    zorder: &[Morton],
    indices: &Vec<[u32; 4]>,
    first: usize,
    last: usize,
) -> BVH {
    if first == last {
        BVH::Leaf(indices[first])
    } else {
        let split = find_split(zorder, first, last);

        let child_a = generate_hierarchy(zorder, indices, first, split);
        let child_b = generate_hierarchy(zorder, indices, split + 1, last);

        BVH::Node(Box::new(child_a), Box::new(child_b))
    }
}

fn find_split(zorder: &[Morton], first: usize, last: usize) -> usize {
    let first_code = &zorder[first];
    let last_code = &zorder[last];

    if first_code == last_code {
        (first + last) / 2
    } else {
        let common_prefix = (*first_code ^ *last_code).leading_zeros();

        // Binary search to find highest object that shares more than common_prefix
        let mut split = first;
        let mut step = last - first;

        while {
            // horrible do-while hack
            step = (step + 1) / 2;
            let new_split = split + step;

            if new_split < last {
                let split_code = &zorder[new_split];
                let split_prefix = (*first_code ^ *split_code).leading_zeros();
                if split_prefix > common_prefix {
                    split = new_split;
                }
            }

            step > 1
        } {}

        split
    }
}
