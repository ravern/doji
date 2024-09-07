pub struct Module {
    pub chunks: Box<[Chunk]>,
}

pub struct Chunk {
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
