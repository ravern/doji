use std::fmt;

use operand::CodeOffset;

pub use crate::constant::Constant;
pub use crate::instruction::Instruction;

use crate::operand::ConstantIndex;

mod constant;
mod instruction;
pub mod operand;

pub struct Program {
    pub constants: Vec<Constant>,
    pub chunks: Vec<Chunk>,
}

impl Program {
    pub fn chunk(&self, index: ChunkIndex) -> Option<&Chunk> {
        self.chunks.get(index.as_usize())
    }

    pub fn constant(&self, index: ConstantIndex) -> Option<&Constant> {
        self.constants.get(index.as_usize())
    }
}

pub struct Chunk {
    pub module_path: String,
    pub name: String,
    pub code: Vec<Instruction>,
}

impl Chunk {
    pub fn instruction(&self, offset: CodeOffset) -> Option<Instruction> {
        self.code.get(offset.as_usize()).copied()
    }

    pub fn len(&self) -> usize {
        self.code.len()
    }
}

#[derive(Clone, Copy, Debug)]
pub struct ChunkIndex(pub usize);

impl ChunkIndex {
    pub fn as_usize(self) -> usize {
        self.0
    }
}

impl fmt::Display for ChunkIndex {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}
