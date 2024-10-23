use std::fmt::{self, Display, Formatter};

#[derive(Debug)]
pub struct Chunk {
    pub arity: Arity,
    pub upvalues: Box<[Upvalue]>,
    pub instructions: Box<[Instruction]>,
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
    Jump(InstructionOffset),

    Call(Arity),
    Return,

    UpvalueLoad(UpvalueIndex),
    UpvalueStore(UpvalueIndex),
    UpvalueClose,

    ObjectGet,
    ObjectSet,
}

macro_rules! define_operand {
    ($name:ident) => {
        #[derive(Clone, Copy, Debug, Eq, PartialEq)]
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

define_operand!(Arity);
define_operand!(InstructionOffset);
define_operand!(IntImmediate);
define_operand!(ConstantIndex);
define_operand!(FunctionIndex);
define_operand!(UpvalueIndex);
define_operand!(StackSlot);
