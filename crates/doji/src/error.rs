use thiserror::Error;

use crate::code::{CodeOffset, ConstantIndex};

#[derive(Debug, Error)]
pub enum Error {
    #[error("{code_offset}: code offset out of bounds")]
    CodeOffsetOutOfBounds { code_offset: CodeOffset },

    #[error("{code_offset}: invalid constant index: {index}")]
    InvalidConstantIndex {
        code_offset: CodeOffset,
        index: ConstantIndex,
    },
}
