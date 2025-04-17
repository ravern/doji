use crate::{error::Error, value::Value};

pub struct Fiber<'gc> {
    stack: FiberStack<'gc>,
}

impl Fiber<'_> {
    pub fn new() -> Self {
        Fiber {
            stack: FiberStack { values: Vec::new() },
        }
    }

    pub fn step(&self) -> Result<(), Error> {
        Ok(())
    }
}

struct FiberStack<'gc> {
    values: Vec<Value<'gc>>,
}
