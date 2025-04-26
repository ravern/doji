use gc_arena::{Collect, Collection, DynamicRootSet, Mutation};

use crate::{
    context::Context,
    driver::Operation,
    value::{RootValue, Value},
};

#[derive(Collect)]
#[collect(no_drop)]
pub struct State<'gc> {
    roots: DynamicRootSet<'gc>,
}

impl<'gc> State<'gc> {
    pub fn new(mutation: &'gc Mutation<'gc>) -> Self {
        Self {
            roots: DynamicRootSet::new(mutation),
        }
    }

    pub fn root(&self, mutation: &Mutation<'gc>, value: Value<'gc>) -> RootValue {
        self.roots.stash(mutation, value)
    }

    pub fn unroot(&self, root: RootValue) -> Value<'gc> {
        *self.roots.fetch(&root)
    }

    pub fn step(&self, cx: &Context<'gc>) -> Step<'gc> {
        Step::Return(Value::NIL)
    }
}

pub enum Step<'gc> {
    Continue,
    Yield(Operation),
    Return(Value<'gc>),
}
