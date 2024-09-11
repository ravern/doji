use std::fmt::{self, Display, Formatter};

use thiserror::Error;

use crate::{
    code::{CodeOffset, ConstantIndex, StackSlot},
    value::ValueType,
};

#[derive(Debug, Error)]
pub enum Error {
    #[error("{code_offset}: code offset out of bounds")]
    CodeOffsetOutOfBounds { code_offset: CodeOffset },

    #[error("{code_offset}: stack underflow")]
    StackUnderflow { code_offset: CodeOffset },

    #[error("{code_offset}: invalid stack slot: {slot}")]
    InvalidStackSlot {
        code_offset: CodeOffset,
        slot: StackSlot,
    },

    #[error("{code_offset}: invalid constant index: {index}")]
    InvalidConstantIndex {
        code_offset: CodeOffset,
        index: ConstantIndex,
    },

    #[error("{code_offset}: wrong type, expected {expected}, found {found}")]
    WrongType {
        code_offset: CodeOffset,
        expected: ValueTypes,
        found: ValueType,
    },
}

#[derive(Debug)]
pub struct ValueTypes(Box<[ValueType]>);

impl<const N: usize> From<[ValueType; N]> for ValueTypes {
    fn from(types: [ValueType; N]) -> ValueTypes {
        ValueTypes(types.into())
    }
}

impl Display for ValueTypes {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        self.0
            .into_iter()
            .map(ToString::to_string)
            .collect::<Box<[String]>>()
            .join(", ")
            .fmt(f)
    }
}
