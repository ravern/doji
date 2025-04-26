use gc_arena::Mutation;

use crate::{
    state::State,
    value::{RootValue, Value},
};

pub struct Context<'gc> {
    mutation: &'gc Mutation<'gc>,
    state: &'gc State<'gc>,
}

impl<'gc> Context<'gc> {
    pub fn new(mutation: &'gc Mutation<'gc>, state: &'gc State<'gc>) -> Self {
        Self { mutation, state }
    }

    pub fn root(&self, value: Value<'gc>) -> RootValue {
        self.state.root(self.mutation, value)
    }

    pub fn unroot(&self, root: RootValue) -> Value<'gc> {
        self.state.unroot(root)
    }
}
