use gc_arena::{Arena as GcArena, Gc, Mutation, Rootable};

use crate::{
    error::Error,
    function::{Function, opcode},
    native::Native,
    state::{self, State},
    value::Value,
};

fn build_function<'gc>(mc: &Mutation<'gc>) -> Gc<'gc, Function<'gc>> {
    let mut builder = Function::builder();
    builder.arity(0);
    builder.instruction(opcode::INT, 3);
    builder.instruction(opcode::INT, 4);
    builder.instruction(opcode::ADD, 0);
    builder.instruction(opcode::RETURN, 0);
    Gc::new(mc, builder.build())
}

pub struct Engine {
    arena: GcArena<Rootable![State<'_>]>,
}

impl Engine {
    pub fn new() -> Self {
        Self {
            arena: GcArena::new(|mc| State::new(mc)),
        }
    }

    pub fn register(&mut self, name: &str, native: Native) -> Result<(), Error> {
        unimplemented!()
    }

    pub fn resolve(&mut self, name: &str, source: Source<'_>) -> Result<(), Error> {
        unimplemented!()
    }

    pub fn evaluate<T>(&mut self, source: Source<'_>) -> Result<T, Error>
    where
        T: for<'gc> TryFrom<Value<'gc>, Error = Error>,
    {
        loop {
            if let Some(step) = self.arena.mutate_root(|mc, state| state.step(mc))? {
                match step {
                    state::Step::Yield(id, op) => {}
                    state::Step::Return(value) => return Ok(value),
                }
            } else {
                std::thread::park();
            }
            self.arena.collect_debt();
        }
    }
}

pub enum Source<'s> {
    File(&'s str),
    Inline(&'s str),
}
