use std::fs::File;
use std::io::{BufRead, BufReader};
use std::ops::Deref;
use std::str::FromStr;

pub struct Model {
    pub vertices: Vec<Vertex>,
    pub indices: Vec<[u32; 3]>,
}

#[derive(Clone, Copy)]
pub struct Vertex {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(PartialEq, Eq)]
enum ParseState {
    Header,
    Vertices,
    Indices,
}

pub fn load_model() -> Model {
    let file = File::open("resources/bunny.ply").unwrap();

    let line_iter = BufReader::new(file).lines();

    let mut state = ParseState::Header;

    let mut vecs: (Vec<Vertex>, Vec<[u32; 3]>) = (vec![], vec![]);
    let mut i: usize = 0;
    let mut vert_count = 0;

    for line in line_iter {
        let l = line.unwrap();
        let s = l.deref();
        match state {
            ParseState::Header => {
                if s.starts_with("element") {
                    let n = s.split_whitespace().skip(2).next().unwrap();
                    let x = usize::from_str_radix(n, 10).unwrap();
                    if i == 0 {
                        vert_count = x;
                        vecs.0.reserve_exact(x);
                    } else {
                        vecs.1.reserve_exact(x);
                    }
                    i = i + 1;
                }
                if s == "end_header" {
                    state = ParseState::Vertices;
                }
            }
            ParseState::Vertices => {
                if vert_count == 1 {
                    state = ParseState::Indices;
                } else {
                    vert_count = vert_count - 1;
                    let mut numbers = s.split_whitespace();
                    vecs.0.push(Vertex {
                        x: f32::from_str(numbers.next().unwrap()).unwrap(),
                        y: f32::from_str(numbers.next().unwrap()).unwrap(),
                        z: f32::from_str(numbers.next().unwrap()).unwrap(),
                    });
                }
            }
            ParseState::Indices => {
                let mut numbers = s.split_whitespace().skip(1);
                vecs.1.push([
                    u32::from_str_radix(numbers.next().unwrap(), 10).unwrap(),
                    u32::from_str_radix(numbers.next().unwrap(), 10).unwrap(),
                    u32::from_str_radix(numbers.next().unwrap(), 10).unwrap(),
                ]);
            }
        }
    }

    Model {
        vertices: vecs.0,
        indices: vecs.1,
    }
}
