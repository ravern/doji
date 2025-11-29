use std::collections::VecDeque;

use gc_arena::{
    Collect, Gc, Mutation,
    lock::{GcRefLock, RefLock},
};
use generational_arena::Arena as GenArena;

use crate::{
    closure::ClosurePtr,
    context::Context,
    driver::Id,
    error::EngineError,
    fiber::{self, FiberPtr, FiberValue},
    value::Value,
};

#[derive(Collect)]
#[collect(no_drop)]
pub struct State<'gc> {
    root_fiber: GcRefLock<'gc, Option<FiberPtr<'gc>>>,
    ready_queue: GcRefLock<'gc, VecDeque<FiberPtr<'gc>>>,
    pending_arena: GcRefLock<'gc, PendingArena<'gc>>,
}

impl<'gc> State<'gc> {
    pub fn new(mutation: &'gc Mutation<'gc>) -> Self {
        Self {
            root_fiber: Gc::new(mutation, RefLock::default()),
            ready_queue: Gc::new(mutation, RefLock::default()),
            pending_arena: Gc::new(mutation, RefLock::default()),
        }
    }

    pub fn spawn(&self, cx: &Context<'gc>, closure: ClosurePtr<'gc>) -> FiberPtr<'gc> {
        let fiber = FiberValue::new_ptr(cx, closure);

        // Set this fiber as the root fiber if there aren't any existing fibers.
        if self.ready_queue.borrow().is_empty() && self.pending_arena.borrow().is_empty() {
            let _ = self.root_fiber.borrow_mut(cx.mutation()).insert(fiber);
        }

        // Enqueue the fiber for evaluation.
        self.ready_queue.borrow_mut(cx.mutation()).push_back(fiber);

        fiber
    }

    pub fn step(&self, cx: &Context<'gc>) -> Step<'gc> {
        // Dequeue the next fiber to be evaluated.
        let fiber = match self.ready_queue.borrow_mut(cx.mutation()).pop_front() {
            Some(fiber) => fiber,
            None => {
                // TODO: we will just return continue for now, which means this will busy-wait
                // until we successfully poll the driver for an event. Ideally we design some kind
                // of non-busy-waiting mechanism.
                //
                // Simply parking the thread at this point could cause a concurrency bug where the
                // unpark is called before the park.
                return Step::Continue;
            }
        };

        // We first insert the fiber into the pending arena to obtain an id for a potential yield.
        let id = self.pending_arena.borrow_mut(cx.mutation()).insert(fiber);

        // We also want to know whether the fiber is the root fiber.
        let is_root_fiber = Gc::ptr_eq(fiber, self.root_fiber.borrow().unwrap());

        // Run one step of the evaluation of the fiber.
        match fiber.borrow_mut(cx.mutation()).step(cx) {
            fiber::Step::Continue => {
                self.pending_arena.borrow_mut(cx.mutation()).remove(id);
                Step::Continue
            }
            fiber::Step::Yield(value) => Step::Yield(id, value),
            fiber::Step::Return(value) => {
                self.pending_arena.borrow_mut(cx.mutation()).remove(id);

                // If the root fiber returns, we're done with this evaluation, otherwise continue.
                if is_root_fiber {
                    // TODO: print a warning if not all fibers have returned before the root fiber.
                    Step::Return(value)
                } else {
                    Step::Continue
                }
            }
        }
    }

    pub fn wake(&self, cx: &Context<'gc>, id: Id, res: Value<'gc>) {
        let fiber = self
            .pending_arena
            .borrow_mut(cx.mutation())
            .remove(id)
            .ok_or(EngineError::WakeNonExistentFiber)
            .unwrap();
        fiber.borrow_mut(cx.mutation()).push(cx, res);
        self.ready_queue.borrow_mut(cx.mutation()).push_back(fiber);
    }
}

pub enum Step<'gc> {
    Continue,
    Yield(Id, Value<'gc>),
    Return(Value<'gc>),
}

#[derive(Default)]
struct PendingArena<'gc>(GenArena<FiberPtr<'gc>>);

impl<'gc> PendingArena<'gc> {
    fn insert(&mut self, fiber: FiberPtr<'gc>) -> Id {
        self.0.insert(fiber).into()
    }

    fn remove(&mut self, id: Id) -> Option<FiberPtr<'gc>> {
        self.0.remove(id.into())
    }

    fn len(&self) -> usize {
        self.0.len()
    }

    fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

unsafe impl<'gc> Collect for PendingArena<'gc> {
    fn needs_trace() -> bool
    where
        Self: Sized,
    {
        true
    }

    fn trace(&self, cc: &gc_arena::Collection) {
        for (_, fiber) in self.0.iter() {
            fiber.trace(cc);
        }
    }
}
