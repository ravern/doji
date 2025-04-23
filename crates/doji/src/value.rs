use gc_arena::{Collect, Gc, lock::GcRefLock};

use crate::{error::Error, fiber::Fiber, function::Function, native::Native};

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    String(Gc<'gc, String>),
    Closure(GcRefLock<'gc, Closure<'gc>>),
    Fiber(GcRefLock<'gc, Fiber<'gc>>),
    Native(Native),
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

impl<'gc> From<i64> for Value<'gc> {
    fn from(value: i64) -> Self {
        Value::Int(value)
    }
}

impl<'gc> From<f64> for Value<'gc> {
    fn from(value: f64) -> Self {
        Value::Float(value)
    }
}

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) struct Closure<'gc> {
    function: Gc<'gc, Function<'gc>>,
    upvalues: Box<[Gc<'gc, Upvalue<'gc>>]>,
}

impl<'gc> Closure<'gc> {
    pub(crate) fn new(
        function: Gc<'gc, Function<'gc>>,
        upvalues: Box<[Gc<'gc, Upvalue<'gc>>]>,
    ) -> Self {
        Closure { function, upvalues }
    }

    pub(crate) fn function(&self) -> &Gc<'gc, Function<'gc>> {
        &self.function
    }

    pub(crate) fn upvalue(&self, index: usize) -> Option<&Gc<'gc, Upvalue<'gc>>> {
        self.upvalues.get(index)
    }
}

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) enum Upvalue<'gc> {
    Open(usize),
    Closed(Value<'gc>),
}
