use gc_arena::{Arena, Collect, Gc, Mutation, Rootable};

use crate::{
    error::Error,
    fiber::{self, Fiber},
    value::Value,
};

pub struct Engine {
    arena: Arena<Rootable![State<'_>]>,
}

impl Engine {
    pub fn new() -> Self {
        Engine {
            arena: Arena::new(|mc| State {
                active_fiber: Gc::new(mc, Fiber::new()),
            }),
        }
    }

    pub fn run<T>(&self, source: &str) -> Result<T, Error>
    where
        T: for<'gc> TryFrom<Value<'gc>, Error = Error>,
    {
        loop {
            let step = self.arena.mutate(|mc, state| state.step::<T>(mc))?;
            if let Step::Done(value) = step {
                return Ok(value);
            }
        }
    }
}

#[derive(Collect)]
#[collect(no_drop)]
struct State<'gc> {
    active_fiber: Gc<'gc, Fiber<'gc>>,
}

impl<'gc> State<'gc> {
    fn step<T>(&self, mc: &Mutation<'gc>) -> Result<Step<T>, Error>
    where
        T: TryFrom<Value<'gc>, Error = Error>,
    {
        match self.active_fiber.step(mc)? {
            fiber::Step::Yield(value) => Ok(Step::Continue),
            fiber::Step::Done(value) => value.try_into().map(Step::Done),
        }
    }
}

enum Step<T> {
    Continue,
    Done(T),
}
