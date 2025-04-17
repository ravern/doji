use gc_arena::Gc;

use crate::error::Error;

pub enum Value<'gc> {
    Bool(bool),
    Int(i64),
    Float(f64),
    String(Gc<'gc, String>),
}

impl TryFrom<Value<'_>> for bool {
    type Error = Error;

    fn try_from(value: Value) -> Result<Self, Self::Error> {
        match value {
            Value::Bool(b) => Ok(b),
            _ => Err(Error::WrongType),
        }
    }
}

impl TryFrom<Value<'_>> for i64 {
    type Error = Error;

    fn try_from(value: Value) -> Result<Self, Self::Error> {
        match value {
            Value::Int(i) => Ok(i),
            _ => Err(Error::WrongType),
        }
    }
}

impl TryFrom<Value<'_>> for f64 {
    type Error = Error;

    fn try_from(value: Value) -> Result<Self, Self::Error> {
        match value {
            Value::Float(f) => Ok(f),
            _ => Err(Error::WrongType),
        }
    }
}

impl<'gc> TryFrom<Value<'gc>> for String {
    type Error = Error;

    fn try_from(value: Value<'gc>) -> Result<Self, Self::Error> {
        match value {
            Value::String(s) => Ok(s.as_ref().clone()),
            _ => Err(Error::WrongType),
        }
    }
}
