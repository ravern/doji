use std::fmt::{self, Display, Formatter};

#[derive(Debug)]
pub struct Chunk {
    pub upvalues: Box<[Upvalue]>,
    pub code: Box<[Instruction]>,
}

#[derive(Clone, Copy, Debug)]
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
    Neq,
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
    Shl,
    Shr,

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
        pub struct $name(pub u32);

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
