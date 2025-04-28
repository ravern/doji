use gc_arena::Mutation;

use crate::{
    ClosurePtr, closure::ClosureValue, compile::compile, error::ErrorPtr, fiber::FiberPtr,
    state::State,
};

pub struct Context<'gc> {
    mutation: &'gc Mutation<'gc>,
    state: &'gc State<'gc>,
}

impl<'gc> Context<'gc> {
    pub fn new(mutation: &'gc Mutation<'gc>, state: &'gc State<'gc>) -> Self {
        Self { mutation, state }
    }

    pub fn compile(&self, source: &str) -> Result<ClosurePtr<'gc>, ErrorPtr<'gc>> {
        let function = compile(self, source.as_ref())?;
        let closure = ClosureValue::new_ptr(self, function);
        Ok(closure)
    }

    pub fn spawn(&self, closure: ClosurePtr<'gc>) -> FiberPtr<'gc> {
        self.state.spawn(self, closure)
    }

    pub(crate) fn mutation(&self) -> &Mutation<'gc> {
        self.mutation
    }

    pub(crate) fn state(&self) -> &State<'gc> {
        self.state
    }
}
