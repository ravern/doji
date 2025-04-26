use gc_arena::{Collect, Gc};

use crate::string::StringPtr;

pub(crate) type FunctionPtr<'gc> = Gc<'gc, Function<'gc>>;

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) struct Function<'gc> {
    name: Option<StringPtr<'gc>>,
    arity: usize,
    constants: Box<[Constant<'gc>]>,
    code: Box<[Instruction]>,
}

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) enum Constant<'gc> {
    Int(i64),
    Float(f64),
    String(StringPtr<'gc>),
}

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) enum Instruction {}
