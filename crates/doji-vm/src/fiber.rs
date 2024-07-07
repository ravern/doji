use std::sync::Arc;

use crate::bytecode::Chunk;

pub struct Fiber {
    chunk: Arc<Chunk>,
    pc: usize,
}

impl Fiber {
    pub fn step(&mut self) {
        let instruction = &self.chunk.code[self.pc];
        match instruction {
            _ => todo!(),
        }
    }
}
