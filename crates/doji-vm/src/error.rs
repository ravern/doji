use std::{error::Error, fmt};

use crate::value::ValueType;

#[derive(Debug)]
pub struct RuntimeErrorContext {
    pub module_path: Box<str>,
    pub chunk_name: Box<str>,
    pub bytecode_offset: usize,
}

impl fmt::Display for RuntimeErrorContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}:{}:{}",
            self.module_path, self.chunk_name, self.bytecode_offset
        )
    }
}

#[derive(Debug)]
pub struct RuntimeError {
    context: RuntimeErrorContext,
    kind: RuntimeErrorKind,
}

impl RuntimeError {
    pub fn invalid_type<E>(context: RuntimeErrorContext, expected: E, received: ValueType) -> Self
    where
        E: Into<Box<[ValueType]>>,
    {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidType {
                expected: expected.into(),
                received,
            },
        }
    }

    pub fn invalid_bytecode_offset(context: RuntimeErrorContext) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidBytecodeOffset,
        }
    }

    pub fn invalid_constant_index(context: RuntimeErrorContext, index: usize) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidConstantIndex(index),
        }
    }

    pub fn invalid_chunk_index(context: RuntimeErrorContext, index: usize) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidChunkIndex(index),
        }
    }

    pub fn invalid_stack_slot(context: RuntimeErrorContext, slot: usize) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::InvalidStackSlot(slot),
        }
    }

    pub fn operand_width_exceeded(context: RuntimeErrorContext) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::OperandWidthExceeded,
        }
    }

    pub fn stack_underflow(context: RuntimeErrorContext) -> Self {
        Self {
            context,
            kind: RuntimeErrorKind::StackUnderfow,
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
    InvalidBytecodeOffset,
    InvalidConstantIndex(usize),
    InvalidChunkIndex(usize),
    InvalidStackSlot(usize),
    InvalidType {
        expected: Box<[ValueType]>,
        received: ValueType,
    },
    OperandWidthExceeded,
    StackUnderfow,
}

impl fmt::Display for RuntimeErrorKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RuntimeErrorKind::InvalidBytecodeOffset => {
                write!(f, "invalid bytecode offset")
            }
            RuntimeErrorKind::InvalidConstantIndex(index) => {
                write!(f, "invalid constant index: {}", index)
            }
            RuntimeErrorKind::InvalidChunkIndex(index) => {
                write!(f, "invalid chunk index: {}", index)
            }
            RuntimeErrorKind::InvalidStackSlot(slot) => write!(f, "invalid stack slot: {}", slot),
            RuntimeErrorKind::InvalidType { expected, received } => {
                write!(
                    f,
                    "invalid type: expected {}, received {}",
                    expected
                        .into_iter()
                        .map(ToString::to_string)
                        .collect::<Vec<String>>()
                        .join(", "),
                    received
                )
            }
            RuntimeErrorKind::OperandWidthExceeded => write!(f, "operand width exceeded"),
            RuntimeErrorKind::StackUnderfow => write!(f, "stack underflow"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_invalid_code_offset() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".into(),
            chunk_name: "main".into(),
            bytecode_offset: 399,
        };
        let error = RuntimeError::invalid_bytecode_offset(context);

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:main:399: invalid code offset"
        );
    }

    #[test]
    fn display_invalid_constant_index() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".into(),
            chunk_name: "main".into(),
            bytecode_offset: 399,
        };
        let error = RuntimeError::invalid_constant_index(context, 42);

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:main:399: invalid constant index: 42"
        );
    }

    #[test]
    fn display_invalid_chunk_index() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".into(),
            chunk_name: "main".into(),
            bytecode_offset: 399,
        };
        let error = RuntimeError::invalid_chunk_index(context, 42);

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:main:399: invalid chunk index: 42"
        );
    }

    #[test]
    fn display_invalid_stack_slot() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".into(),
            chunk_name: "main".into(),
            bytecode_offset: 399,
        };
        let error = RuntimeError::invalid_stack_slot(context, 42);

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:main:399: invalid stack slot: 42"
        );
    }

    #[test]
    fn display_invalid_type() {
        let context = RuntimeErrorContext {
            module_path: "src/main.doji".into(),
            chunk_name: "main".into(),
            bytecode_offset: 399,
        };
        let error = RuntimeError::invalid_type(
            context,
            [ValueType::Int, ValueType::Float],
            ValueType::Bool,
        );

        assert_eq!(
            error.to_string(),
            "runtime error: src/main.doji:main:399: invalid type: expected int, float, received bool"
        );
    }
}
