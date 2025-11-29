use core::fmt::{self, Display, Formatter};

use gc_arena::{Collect, Gc};

use crate::{context::Context, string::StringPtr, value::Value};

pub type ErrorPtr<'gc> = Gc<'gc, ErrorValue<'gc>>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct ErrorValue<'gc> {
    message: StringPtr<'gc>,
    data: Value<'gc>,
    trace: (),
}

impl<'gc> ErrorValue<'gc> {
    pub fn new_ptr(cx: &Context<'gc>, message: StringPtr<'gc>, data: Value<'gc>) -> ErrorPtr<'gc> {
        Gc::new(
            cx.mutation(),
            Self {
                message,
                data,
                trace: (),
            },
        )
    }
}

impl<'gc> Display for ErrorValue<'gc> {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

pub struct Error {
    message: String,
    trace: (),
}

impl Display for Error {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl<'gc> From<ErrorPtr<'gc>> for Error {
    fn from(error: ErrorPtr<'gc>) -> Self {
        Self {
            message: error.message.to_string(),
            trace: error.trace,
        }
    }
}

#[derive(Debug)]
pub enum EngineError {
    InvalidInstructionOffset(usize),
    InvalidConstantIndex(usize),
    WakeNonExistentFiber,
    StackUnderflow,
    CallStackUnderflow,
}

impl Display for EngineError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            EngineError::InvalidInstructionOffset(offset) => {
                write!(f, "invalid instruction offset: {}", offset)
            }
            EngineError::InvalidConstantIndex(index) => {
                write!(f, "invalid constant index: {}", index)
            }
            EngineError::WakeNonExistentFiber => write!(f, "tried to wake a non-existent fiber"),
            EngineError::StackUnderflow => write!(f, "stack underflow"),
            EngineError::CallStackUnderflow => write!(f, "call stack underflow"),
        }
    }
}
