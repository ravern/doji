use gc_arena::{Collect, Gc};

use crate::{context::Context, function::FunctionPtr, value::Value};

pub type ClosurePtr<'gc> = Gc<'gc, ClosureValue<'gc>>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct ClosureValue<'gc> {
    function: FunctionPtr<'gc>,
    upvalues: Box<[UpvaluePtr<'gc>]>,
}

impl<'gc> ClosureValue<'gc> {
    pub fn new_ptr(cx: &Context<'gc>, function: FunctionPtr<'gc>) -> ClosurePtr<'gc> {
        Gc::new(
            cx.mutation(),
            Self {
                function,
                upvalues: Box::new([]),
            },
        )
    }

    pub fn ptr_with_upvalues(
        cx: &Context<'gc>,
        function: FunctionPtr<'gc>,
        upvalues: Box<[UpvaluePtr<'gc>]>,
    ) -> ClosurePtr<'gc> {
        Gc::new(cx.mutation(), Self { function, upvalues })
    }

    pub fn function(&self) -> FunctionPtr<'gc> {
        self.function
    }
}

pub type UpvaluePtr<'gc> = Gc<'gc, Upvalue<'gc>>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub enum Upvalue<'gc> {
    Open(usize),
    Closed(Value<'gc>),
}
