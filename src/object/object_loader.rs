use std::fs::File;
use std::io::{BufRead, BufReader};
use std::ops::Deref;
use std::str::FromStr;

#[derive(PartialEq, Eq)]
enum ParseState {
    Header,
    Vertices,
    Indices,
}

pub fn load_model(path: &str) -> (Vec<[f32; 4]>, Vec<[u32; 4]>) {
    let file = File::open(path).unwrap();

    let line_iter = BufReader::new(file).lines();

    let mut state = ParseState::Header;

    let mut vecs: (Vec<[f32; 4]>, Vec<[u32; 4]>) = (vec![], vec![]);
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
                vert_count = vert_count - 1;
                let mut numbers = s.split_whitespace();
                vecs.0.push([
                    f32::from_str(numbers.next().unwrap()).unwrap(),
                    f32::from_str(numbers.next().unwrap()).unwrap(),
                    f32::from_str(numbers.next().unwrap()).unwrap(),
                    0.0,
                ]);
                if vert_count == 0 {
                    state = ParseState::Indices;
                }
            }
            ParseState::Indices => {
                let mut numbers = s.split_whitespace().skip(1);
                vecs.1.push([
                    u32::from_str_radix(numbers.next().unwrap(), 10).unwrap(),
                    u32::from_str_radix(numbers.next().unwrap(), 10).unwrap(),
                    u32::from_str_radix(numbers.next().unwrap(), 10).unwrap(),
                    0,
                ]);
            }
        }
    }

    vecs
}
