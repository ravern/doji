use std::marker::PhantomData;

use crate::{error::Error, value::Value};
use gc_arena::{Arena, Collect, Rootable};

pub struct Engine {
    state: Arena<Rootable![EngineState<'_>]>,
}

impl Engine {
    pub fn new() -> Self {
        Engine {
            state: Arena::new(|mc| EngineState {
                marker: PhantomData,
            }),
        }
    }

    pub fn run(&self, source: &str) -> Result<Value, Error> {
        Ok(Value::Int(42))
    }
}

#[derive(Collect)]
#[collect(no_drop)]
struct EngineState<'gc> {
    marker: PhantomData<&'gc ()>,
}
