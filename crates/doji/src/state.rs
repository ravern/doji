use std::collections::VecDeque;

use gc_arena::{Collect, DynamicRoot, DynamicRootSet, Mutation, Rootable, lock::GcRefLock};

use crate::{
    error::Error,
    fiber::{self, Fiber},
    io,
    value::Value,
};

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) struct State<'gc> {
    ready_queue: VecDeque<GcRefLock<'gc, Fiber<'gc>>>,
    pending_fibers: DynamicRootSet<'gc>,
}

impl<'gc> State<'gc> {
    pub(crate) fn new(mc: &Mutation<'gc>) -> Self {
        Self {
            ready_queue: VecDeque::new(),
            pending_fibers: DynamicRootSet::new(mc),
        }
    }

    pub(crate) fn step<T>(&mut self, mc: &Mutation<'gc>) -> Result<Option<Step<T>>, Error>
    where
        T: TryFrom<Value<'gc>, Error = Error>,
    {
        let fiber = match self.ready_queue.pop_front() {
            Some(fiber) => fiber,
            None => return Ok(None),
        };

        let pending_fiber = self.pending_fibers.stash(mc, fiber);

        match fiber.borrow_mut(mc).step(mc)? {
            fiber::Step::Yield(op) => return Ok(Some(Step::Yield(pending_fiber, op))),
            fiber::Step::Return(value) => {
                return value.try_into().map(Step::Return).map(Some);
            }
        }
    }

    pub(crate) fn wake(
        &mut self,
        pending_fiber: &DynamicRoot<Rootable![GcRefLock<'_, Fiber<'_>>]>,
    ) {
        let fiber = self.pending_fibers.fetch(pending_fiber);
        self.ready_queue.push_back(*fiber);
    }
}

pub(crate) enum Step<T> {
    Yield(
        DynamicRoot<Rootable![GcRefLock<'_, Fiber<'_>>]>,
        io::Operation,
    ),
    Return(T),
}
