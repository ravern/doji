use gc_arena::{Collect, Gc};

use crate::{closure::ClosurePtr, context::Context};

pub type FiberPtr<'gc> = Gc<'gc, FiberValue<'gc>>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct FiberValue<'gc> {
    closure: ClosurePtr<'gc>,
}

impl<'gc> FiberValue<'gc> {
    pub fn new_ptr(cx: &Context<'gc>, closure: ClosurePtr<'gc>) -> FiberPtr<'gc> {
        Gc::new(cx.mutation(), Self { closure })
    }
}
