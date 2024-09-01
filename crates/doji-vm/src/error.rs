use std::{error::Error, fmt};

use doji_bytecode::{
    operand::{CodeOffset, ConstantIndex, StackSlot},
    ChunkIndex,
};

use crate::value::ValueType;

#[derive(Debug)]
pub struct RuntimeErrorContext {
    pub module_path: String,
    pub code_offset: CodeOffset,
}

impl fmt::Display for RuntimeErrorContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", self.module_path, self.code_offset.as_usize())
    }
}

#[derive(Debug)]
pub struct RuntimeError {
    context: RuntimeErrorContext,
    kind: RuntimeErrorKind,
}

impl RuntimeError {
    pub fn invalid_type(
        context: RuntimeErrorContext,
        expected: ValueType,
        received: ValueType,
    ) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidType { expected, received },
        }
    }

    pub fn invalid_code_offset(context: RuntimeErrorContext) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidBytecode(InvalidBytecode::CodeOffset),
        }
    }

    pub fn invalid_constant_index(context: RuntimeErrorContext, index: ConstantIndex) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidBytecode(InvalidBytecode::ConstantIndex(index)),
        }
    }

    pub fn invalid_chunk_index(context: RuntimeErrorContext, index: ChunkIndex) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidBytecode(InvalidBytecode::ChunkIndex(index)),
        }
    }

    pub fn invalid_stack_slot(context: RuntimeErrorContext, slot: StackSlot) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidBytecode(InvalidBytecode::StackSlot(slot)),
        }
    }

    pub fn context(&self) -> &RuntimeErrorContext {
        &self.context
    }

    pub fn kind(&self) -> &RuntimeErrorKind {
        &self.kind
    }
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "runtime error: {}: {}", self.context, self.kind)
    }
}

impl Error for RuntimeError {}

#[derive(Debug)]
pub enum RuntimeErrorKind {
    InvalidBytecode(InvalidBytecode),
    InvalidType {
        expected: ValueType,
        received: ValueType,
    },
}

impl fmt::Display for RuntimeErrorKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RuntimeErrorKind::InvalidBytecode(invalid_bytecode) => {
                write!(f, "{}", invalid_bytecode)
            }
            RuntimeErrorKind::InvalidType { expected, received } => {
                write!(
                    f,
                    "invalid type: expected {}, received {}",
                    expected, received
                )
            }
        }
    }
}

#[derive(Debug)]
pub enum InvalidBytecode {
    CodeOffset,
    ConstantIndex(ConstantIndex),
    ChunkIndex(ChunkIndex),
    StackSlot(StackSlot),
}

impl fmt::Display for InvalidBytecode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InvalidBytecode::CodeOffset => write!(f, "invalid code offset"),
            InvalidBytecode::ConstantIndex(index) => write!(f, "invalid constant index: {}", index),
            InvalidBytecode::ChunkIndex(index) => write!(f, "invalid chunk index: {}", index),
            InvalidBytecode::StackSlot(slot) => write!(f, "invalid stack slot: {}", slot),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_invalid_code_offset() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".to_string(),
            code_offset: CodeOffset(399),
        };
        let error = RuntimeError::invalid_code_offset(context);

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:399: invalid code offset"
        );
    }

    #[test]
    fn display_invalid_constant_index() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".to_string(),
            code_offset: CodeOffset(399),
        };
        let error = RuntimeError::invalid_constant_index(context, ConstantIndex(42));

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:399: invalid constant index: 42"
        );
    }

    #[test]
    fn display_invalid_chunk_index() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".to_string(),
            code_offset: CodeOffset(399),
        };
        let error = RuntimeError::invalid_chunk_index(context, ChunkIndex(42));

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:399: invalid chunk index: 42"
        );
    }

    #[test]
    fn display_invalid_stack_slot() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".to_string(),
            code_offset: CodeOffset(399),
        };
        let error = RuntimeError::invalid_stack_slot(context, StackSlot(42));

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:399: invalid stack slot: 42"
        );
    }

    #[test]
    fn display_invalid_type() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".to_string(),
            code_offset: CodeOffset(399),
        };
        let error = RuntimeError::invalid_type(context, ValueType::Int, ValueType::Float);

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:399: invalid type: expected int, received float"
        );
    }
}
