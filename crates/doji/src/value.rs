use gc_arena::{Collect, Gc};

use crate::{error::Error, function::Function};

#[derive(Collect)]
#[collect(no_drop)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    String(Gc<'gc, String>),
    Closure(Gc<'gc, Closure<'gc>>),
}

impl<'gc> TryFrom<Value<'gc>> for bool {
    type Error = Error;

    fn try_from(value: Value) -> Result<Self, Self::Error> {
        match value {
            Value::Bool(b) => Ok(b),
            _ => Err(Error::WrongType),
        }
    }
}

impl<'gc> TryFrom<Value<'gc>> for i64 {
    type Error = Error;

    fn try_from(value: Value) -> Result<Self, Self::Error> {
        match value {
            Value::Int(i) => Ok(i),
            _ => Err(Error::WrongType),
        }
    }
}

impl<'gc> TryFrom<Value<'gc>> for f64 {
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

#[derive(Collect)]
#[collect(no_drop)]
pub struct Closure<'gc> {
    function: Gc<'gc, Function<'gc>>,
    upvalues: Box<[Upvalue<'gc>]>,
}

#[derive(Collect)]
#[collect(no_drop)]
pub enum Upvalue<'gc> {
    Open(usize),
    Closed(Value<'gc>),
}
