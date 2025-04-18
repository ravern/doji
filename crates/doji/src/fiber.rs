use gc_arena::{Collect, Gc, Mutation};

use crate::{
    error::Error,
    value::{Closure, Value},
};

#[derive(Collect)]
#[collect(no_drop)]
pub struct Fiber<'gc> {
    stack: Vec<Value<'gc>>,
    call_stack: Vec<Frame<'gc>>,
}

impl<'gc> Fiber<'gc> {
    pub fn new() -> Self {
        Fiber {
            stack: Vec::new(),
            call_stack: Vec::new(),
        }
    }

    pub fn step(&self, mc: &Mutation<'gc>) -> Result<Step<'gc>, Error> {
        assert!(!self.call_stack.is_empty(), "Call stack is empty");

        Ok(Step::Done(Value::String(Gc::new(
            mc,
            "Hello, world!".to_string(),
        ))))
    }
}

pub enum Step<'gc> {
    Yield(Value<'gc>),
    Done(Value<'gc>),
}

#[derive(Collect)]
#[collect(no_drop)]
struct Frame<'gc> {
    callable: Callable<'gc>,
    ip: usize,
    bp: usize,
}

#[derive(Collect)]
#[collect(no_drop)]
enum Callable<'gc> {
    Closure(Gc<'gc, Closure<'gc>>),
}
