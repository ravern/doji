use std::collections::VecDeque;

use gc_arena::{Arena as GcArena, Collect, Collection, Gc, Mutation, Rootable, lock::GcRefLock};
use generational_arena::Arena as GenArena;

use crate::{
    error::Error,
    fiber::{self, Fiber},
    function::{Function, opcode},
    native::Native,
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
            match self.arena.mutate_root(|mc, state| state.step(mc))? {
                Step::Continue => {}
                Step::Done(value) => return Ok(value),
            }
            self.arena.collect_debt();
        }
    }
}

pub struct State<'gc> {
    root_fiber: Option<GcRefLock<'gc, Fiber<'gc>>>,
    ready_queue: VecDeque<GcRefLock<'gc, Fiber<'gc>>>,
    pending_arena: GenArena<GcRefLock<'gc, Fiber<'gc>>>,
}

impl<'gc> State<'gc> {
    fn new(mc: &Mutation<'gc>) -> Self {
        Self {
            root_fiber: None,
            ready_queue: VecDeque::new(),
            pending_arena: GenArena::new(),
        }
    }

    fn step<T>(&mut self, mc: &Mutation<'gc>) -> Result<Step<T>, Error>
    where
        T: TryFrom<Value<'gc>, Error = Error>,
    {
        let root_fiber = self.root_fiber.expect("root fiber not yet spawned");

        let fiber = match self.ready_queue.pop_front() {
            Some(fiber) => fiber,
            None => return Ok(Step::Continue),
        };

        let index = self.pending_arena.insert(fiber);

        match fiber.borrow_mut(mc).step(mc)? {
            fiber::Step::Yield(operation) => {
                self.pending_arena.insert(fiber);
            }
            fiber::Step::Return(value) => {
                return value.try_into().map(Step::Done);
            }
        }

        Ok(Step::Continue)
    }
}

enum Step<T> {
    Continue,
    Done(T),
}

unsafe impl<'gc> Collect for State<'gc> {
    #[inline]
    fn needs_trace() -> bool {
        true
    }

    #[inline]
    fn trace(&self, cc: &Collection) {
        self.root_fiber.trace(cc);
        self.ready_queue.trace(cc);
        for (_, fiber) in self.pending_arena.iter() {
            fiber.trace(cc);
        }
    }
}

pub enum Source<'s> {
    File(&'s str),
    Inline(&'s str),
}
