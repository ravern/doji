use std::mem::size_of;

pub use crate::constant::Constant;

mod constant;
pub mod opcode;

pub const OPERAND_WIDTH: usize = size_of::<u64>();

pub struct Program {
    pub constants: Box<[Constant]>,
    pub chunks: Box<[Chunk]>,
}

impl Program {
    pub fn constant(&self, index: usize) -> Option<&Constant> {
        self.constants.get(index)
    }

    pub fn chunk(&self, index: usize) -> Option<&Chunk> {
        self.chunks.get(index)
    }
}

pub struct Chunk {
    pub module_path: Box<str>,
    pub name: Box<str>,
    pub bytecode: Box<[u8]>,
}

impl Chunk {
    pub fn byte(&self, offset: usize) -> Option<u8> {
        self.bytecode.get(offset).copied()
    }

    pub fn size(&self) -> usize {
        self.bytecode.len()
    }
}
