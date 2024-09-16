use std::fmt::{self, Display, Formatter};

use crate::{
    code::{CodeOffset, ConstantIndex, FunctionIndex, StackSlot, UpvalueIndex},
    fiber::AbsoluteStackSlot,
    value::TypeError,
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

impl Display for Error {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        write!(f, "{}: ", self.context.code_offset)?;
        match &self.kind {
            ErrorKind::CodeOffsetOutOfBounds => write!(f, "code offset out of bounds"),
            ErrorKind::StackUnderflow => write!(f, "stack underflow"),
            ErrorKind::InvalidAbsoluteStackSlot(slot) => {
                write!(f, "invalid absolute stack slot: {}", slot)
            }
            ErrorKind::FirstStackSlotNotClosure => {
                write!(f, "expected first stack slot to be a closure")
            }
            ErrorKind::InvalidStackSlot(slot) => write!(f, "invalid stack slot: {}", slot),
            ErrorKind::InvalidConstantIndex(index) => {
                write!(f, "invalid constant index: {}", index)
            }
            ErrorKind::InvalidFunctionIndex(index) => {
                write!(f, "invalid function index: {}", index)
            }
            ErrorKind::InvalidUpvalueIndex(index) => {
                write!(f, "invalid upvalue index: {}", index)
            }
            ErrorKind::WrongType(error) => write!(f, "{}", error),
            ErrorKind::WrongArity { expected, found } => {
                write!(f, "wrong arity: expected {}, found {}", expected, found)
            }
        }
    }
}

#[derive(Debug)]
pub struct ErrorContext {
    pub code_offset: CodeOffset,
}

#[derive(Debug)]
pub enum ErrorKind {
    CodeOffsetOutOfBounds,
    StackUnderflow,
    InvalidStackSlot(StackSlot),
    FirstStackSlotNotClosure,
    InvalidAbsoluteStackSlot(AbsoluteStackSlot),
    InvalidConstantIndex(ConstantIndex),
    InvalidFunctionIndex(FunctionIndex),
    InvalidUpvalueIndex(UpvalueIndex),
    WrongType(TypeError),
    WrongArity { expected: u8, found: u8 },
}
