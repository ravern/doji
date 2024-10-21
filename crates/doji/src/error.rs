use std::fmt::{self, Display, Formatter};

use crate::{
    bytecode::{Arity, ConstantIndex, FunctionIndex, InstructionOffset, StackSlot, UpvalueIndex},
    fiber::AbsoluteStackSlot,
    value::{Function, TypeError},
};

#[derive(Debug)]
pub struct Error {
    context: ErrorContext,
    kind: ErrorKind,
}

impl Error {
    pub fn new(context: ErrorContext, kind: ErrorKind) -> Error {
        Error { context, kind }
    }

    pub fn context(&self) -> &ErrorContext {
        &self.context
    }

    pub fn kind(&self) -> &ErrorKind {
        &self.kind
    }
}

#[derive(Debug)]
pub struct ErrorContext {
    pub function: Function,
    pub instruction_offset: InstructionOffset,
}

#[derive(Debug)]
pub enum ErrorKind {
    StackUnderflow,
    FirstStackSlotNotClosure,
    InstructionOffset,
    StackSlot(StackSlot),
    AbsoluteStackSlot(AbsoluteStackSlot),
    ConstantIndex(ConstantIndex),
    FunctionIndex(FunctionIndex),
    UpvalueIndex(UpvalueIndex),
    WrongArity { expected: Arity, found: Arity },
    WrongType(TypeError),
}

impl Display for Error {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        write!(f, "{}: ", self.context.instruction_offset)?;
        match &self.kind {
            ErrorKind::InstructionOffset => write!(f, "invalid instruction offset"),
            ErrorKind::StackUnderflow => write!(f, "stack underflow"),
            ErrorKind::AbsoluteStackSlot(slot) => {
                write!(f, "invalid absolute stack slot: {}", slot)
            }
            ErrorKind::FirstStackSlotNotClosure => {
                write!(f, "expected first stack slot to be a closure")
            }
            ErrorKind::StackSlot(slot) => write!(f, "invalid stack slot: {}", slot),
            ErrorKind::ConstantIndex(index) => {
                write!(f, "invalid constant index: {}", index)
            }
            ErrorKind::FunctionIndex(index) => {
                write!(f, "invalid function index: {}", index)
            }
            ErrorKind::UpvalueIndex(index) => {
                write!(f, "invalid upvalue index: {}", index)
            }
            ErrorKind::WrongType(error) => write!(f, "{}", error),
            ErrorKind::WrongArity { expected, found } => {
                write!(f, "wrong arity: expected {}, found {}", expected, found)
            }
        }
    }
}
