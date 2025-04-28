use std::{cell::RefCell, collections::VecDeque};

use gc_arena::{
    Collect, DynamicRootSet, Gc, Mutation,
    lock::{GcRefLock, RefLock},
};

use crate::{
    closure::ClosurePtr,
    context::Context,
    driver::Id,
    fiber::{FiberPtr, FiberValue},
    value::Value,
};

#[derive(Collect)]
#[collect(no_drop)]
pub struct State<'gc> {
    roots: DynamicRootSet<'gc>,
    ready_queue: GcRefLock<'gc, VecDeque<FiberPtr<'gc>>>,
}

impl<'gc> State<'gc> {
    pub fn new(mutation: &'gc Mutation<'gc>) -> Self {
        Self {
            roots: DynamicRootSet::new(mutation),
            ready_queue: Gc::new(mutation, RefLock::default()),
        }
    }

    pub fn spawn(&self, cx: &Context<'gc>, closure: ClosurePtr<'gc>) -> FiberPtr<'gc> {
        let fiber = FiberValue::new_ptr(cx, closure);
        self.ready_queue.borrow_mut(cx.mutation()).push_back(fiber);
        fiber
    }

    pub fn step(&self, cx: &Context<'gc>) -> Step<'gc> {
        Step::Return(Value::NIL)
    }

    pub fn wake(&self, cx: &Context<'gc>, id: Id, res: Value<'gc>) {
        todo!()
    }
}

pub enum Step<'gc> {
    Continue,
    Yield(Id, Value<'gc>),
    Return(Value<'gc>),
}
