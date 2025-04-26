use core::fmt::{self, Display, Formatter};

use crate::{driver::Driver, resolver::Resolver, value::ValueType};

#[derive(Debug)]
pub enum Error<R, D>
where
    R: Resolver,
    D: Driver,
{
    Engine(EngineError<R, D>),
    Type(TypeError),
}

impl<R, D> Display for Error<R, D>
where
    R: Resolver,
    D: Driver,
{
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::Engine(e) => write!(f, "{}", e),
            Self::Type(e) => write!(f, "{}", e),
        }
    }
}

impl<R, D> From<EngineError<R, D>> for Error<R, D>
where
    R: Resolver,
    D: Driver,
{
    fn from(e: EngineError<R, D>) -> Self {
        Self::Engine(e)
    }
}

impl<R, D> From<TypeError> for Error<R, D>
where
    R: Resolver,
    D: Driver,
{
    fn from(e: TypeError) -> Self {
        Self::Type(e)
    }
}

#[derive(Debug)]
pub enum EngineError<R, D>
where
    R: Resolver,
    D: Driver,
{
    Driver(D::Error),
    Resolver(R::Error),
}

impl<R, D> Display for EngineError<R, D>
where
    R: Resolver,
    D: Driver,
{
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::Driver(e) => write!(f, "{}", e),
            Self::Resolver(e) => write!(f, "{}", e),
        }
    }
}

#[derive(Debug)]
pub struct TypeError {
    pub expected: ValueType,
    pub actual: ValueType,
}

impl Display for TypeError {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "tried to convert {} to {}", self.actual, self.expected)
    }
}
