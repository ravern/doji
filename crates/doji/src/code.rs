use std::fmt::{self, Display, Formatter};

#[derive(Debug)]
pub struct Chunk {
    pub arity: u8,
    pub code: Box<[Instruction]>,
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
    Dup,
    Pop,

    Test,
    Jump(CodeOffset),

    Call(u8),
    Ret,

    UpvalueLoad(UpvalueIndex),
    UpvalueStore(UpvalueIndex),
    UpvalueClose,

    FiberResume,
    FiberYield,

    ValueLen,
    ValueGet,
    ValueSet,
    ValueAppend,
}

macro_rules! define_operand {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug)]
        pub struct $name(u32);

        impl $name {
            pub fn as_usize(self) -> usize {
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
    arity: u8,
    code: Vec<Instruction>,
}

impl ChunkBuilder {
    pub fn new(arity: u8) -> ChunkBuilder {
        ChunkBuilder {
            arity,
            code: Vec::new(),
        }
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
            arity: self.arity,
            code: self.code.into(),
        }
    }
}
