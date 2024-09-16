use std::fmt::{self, Display, Formatter};

#[derive(Debug)]
pub struct Chunk {
    pub upvalues: Box<[Upvalue]>,
    pub code: Box<[Instruction]>,
}

#[derive(Debug)]
pub enum Upvalue {
    Local(StackSlot),
    Upvalue(UpvalueIndex),
}

#[derive(Clone, Copy, Debug)]
pub enum Instruction {
    Noop,

    Nil,
    True,
    False,
    List,
    Map,
    Fiber,
    Int(IntImmediate),
    Constant(ConstantIndex),
    Closure(FunctionIndex),

    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Eq,
    Gt,
    Gte,
    Lt,
    Lte,
    And,
    Or,
    Neg,
    Not,
    BitAnd,
    BitOr,
    BitNot,
    BitXor,

    Load(StackSlot),
    Store(StackSlot),
    Duplicate,
    Pop,

    Test,
    Jump(CodeOffset),

    Call(u8),
    Return,

    UpvalueLoad(UpvalueIndex),
    UpvalueStore(UpvalueIndex),
    UpvalueClose,
}

macro_rules! define_operand {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug)]
        pub struct $name(u32);

        impl $name {
            pub fn into_usize(self) -> usize {
                self.into()
            }
        }

        impl From<usize> for $name {
            fn from(index: usize) -> $name {
                $name(index as u32)
            }
        }

        impl Into<usize> for $name {
            fn into(self) -> usize {
                self.0 as usize
            }
        }

        impl Display for $name {
            fn fmt(&self, f: &mut Formatter) -> fmt::Result {
                write!(f, "{}", self.0)
            }
        }
    };
}

define_operand!(CodeOffset);
define_operand!(IntImmediate);
define_operand!(FunctionIndex);
define_operand!(UpvalueIndex);
define_operand!(StackSlot);
define_operand!(ConstantIndex);

pub struct ChunkBuilder {
    upvalues: Vec<Upvalue>,
    code: Vec<Instruction>,
}

impl ChunkBuilder {
    pub fn new() -> ChunkBuilder {
        ChunkBuilder {
            upvalues: Vec::new(),
            code: Vec::new(),
        }
    }

    pub fn upvalue(mut self, upvalue: Upvalue) -> ChunkBuilder {
        self.upvalues.push(upvalue);
        self
    }

    pub fn code<I>(mut self, instructions: I) -> ChunkBuilder
    where
        I: IntoIterator<Item = Instruction>,
    {
        self.code.extend(instructions);
        self
    }

    pub fn build(self) -> Chunk {
        Chunk {
            upvalues: self.upvalues.into(),
            code: self.code.into(),
        }
    }
}
