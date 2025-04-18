use gc_arena::{Arena, Collect, Gc, Mutation, Rootable, lock::RefLock};

use crate::{
    error::Error,
    fiber::{self, Fiber},
    function::{self, opcode},
    value::{Closure, Value},
};

pub struct Engine {
    arena: Arena<Rootable![State<'_>]>,
}

impl Engine {
    pub fn new() -> Self {
        Engine {
            arena: Arena::new(|mc| State {
                root_fiber: Gc::new(
                    mc,
                    RefLock::new(Fiber::new(Gc::new(
                        mc,
                        Closure::new(
                            Gc::new(mc, {
                                let mut builder = function::Builder::new();
                                builder.instruction(opcode::INT, 3);
                                builder.instruction(opcode::INT, 4);
                                builder.instruction(opcode::ADD, 0);
                                builder.instruction(opcode::RETURN, 0);
                                builder.arity(0);
                                builder.build()
                            }),
                            Box::new([]),
                        ),
                    ))),
                ),
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
    root_fiber: Gc<'gc, RefLock<Fiber<'gc>>>,
}

impl<'gc> State<'gc> {
    fn step<T>(&self, mc: &Mutation<'gc>) -> Result<Step<T>, Error>
    where
        T: TryFrom<Value<'gc>, Error = Error>,
    {
        match self.root_fiber.borrow_mut(mc).step(mc)? {
            fiber::Step::Yield(value) => Ok(Step::Continue),
            fiber::Step::Done(value) => value.try_into().map(Step::Done),
        }
    }
}

enum Step<T> {
    Continue,
    Done(T),
}
