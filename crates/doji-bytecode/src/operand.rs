use std::fmt;

#[derive(Clone, Copy, Debug)]
pub struct StackSlot(pub u16);

impl StackSlot {
    pub fn as_usize(self) -> usize {
        self.0 as usize
    }
}

impl fmt::Display for StackSlot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct IntImmediate(pub i32);

impl IntImmediate {
    pub fn as_i64(self) -> i64 {
        self.0 as i64
    }
}

impl fmt::Display for IntImmediate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct ConstantIndex(pub u32);

impl ConstantIndex {
    pub fn as_usize(self) -> usize {
        self.0 as usize
    }
}

impl fmt::Display for ConstantIndex {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct UpvalueIndex(pub u16);

impl UpvalueIndex {
    pub fn as_usize(self) -> usize {
        self.0 as usize
    }
}

impl fmt::Display for UpvalueIndex {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

#[derive(Clone, Copy, Debug)]
pub struct CodeOffset(pub u32);

impl CodeOffset {
    pub fn zero() -> CodeOffset {
        Self(0)
    }

    pub fn increment(self) -> CodeOffset {
        Self(self.0 + 1)
    }

    pub fn as_usize(self) -> usize {
        self.0 as usize
    }
}

impl fmt::Display for CodeOffset {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}
