extern crate alloc;
use alloc::boxed::Box;
use std::fmt::{self, Display, Formatter};

use crate::value::ValueType;

#[derive(Debug)]
pub enum Error {
    Engine(EngineError),
    InvalidImport,
    WrongType(WrongTypeError),
}

impl Display for Error {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::Engine(err) => write!(f, "{}", err),
            Self::InvalidImport => write!(f, "invalid import"),
            Self::WrongType(err) => write!(f, "{}", err),
        }
    }
}

impl From<EngineError> for Error {
    fn from(e: EngineError) -> Self {
        Self::Engine(e)
    }
}

impl From<WrongTypeError> for Error {
    fn from(e: WrongTypeError) -> Self {
        Self::WrongType(e)
    }
}

#[derive(Debug)]
pub enum EngineError {}

impl Display for EngineError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        Ok(())
    }
}

#[derive(Debug)]
pub struct WrongTypeError {
    pub expected: ValueType,
    pub actual: ValueType,
}

impl Display for WrongTypeError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "tried to convert {} to {}", self.actual, self.expected)
    }
}
