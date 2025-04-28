use std::collections::VecDeque;

use gc_arena::{
    Collect, DynamicRootSet, Gc, Mutation,
    lock::{GcRefLock, RefLock},
};
use generational_arena::Arena as GenArena;

use crate::{
    closure::ClosurePtr,
    context::Context,
    driver::Id,
    fiber::{self, FiberPtr, FiberValue},
    value::Value,
};

#[derive(Collect)]
#[collect(no_drop)]
pub struct State<'gc> {
    roots: DynamicRootSet<'gc>,
    root_fiber: GcRefLock<'gc, Option<FiberPtr<'gc>>>,
    ready_queue: GcRefLock<'gc, VecDeque<FiberPtr<'gc>>>,
    pending_arena: GcRefLock<'gc, PendingArena<'gc>>,
}

impl<'gc> State<'gc> {
    pub fn new(mutation: &'gc Mutation<'gc>) -> Self {
        Self {
            roots: DynamicRootSet::new(mutation),
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
                return Step::Park;
            }
        };

        // We first insert the fiber into the pending arena to obtain an id for a potential yield.
        let id = self.pending_arena.borrow_mut(cx.mutation()).insert(fiber);

        // Run one step of the evaluation of the fiber.
        match fiber.step(cx) {
            fiber::Step::Continue => {
                self.pending_arena.borrow_mut(cx.mutation()).remove(id);
                Step::Continue
            }
            fiber::Step::Yield(value) => Step::Yield(id, value),
            fiber::Step::Return(value) => {
                self.pending_arena.borrow_mut(cx.mutation()).remove(id);
                Step::Return(value)
            }
        }
    }

    pub fn wake(&self, cx: &Context<'gc>, id: Id, res: Value<'gc>) {
        let fiber = self
            .pending_arena
            .borrow_mut(cx.mutation())
            .remove(id)
            .expect("tried to wake a non-existent fiber");
        self.ready_queue.borrow_mut(cx.mutation()).push_back(fiber);
    }
}

pub enum Step<'gc> {
    Park,
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
