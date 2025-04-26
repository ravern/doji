use alloc::boxed::Box;
use gc_arena::{Collect, Gc};

use crate::string::StringPtr;

pub type FunctionPtr<'gc> = Gc<'gc, Function<'gc>>;

#[derive(Collect)]
#[collect(no_drop)]
pub struct Function<'gc> {
    name: Option<StringPtr<'gc>>,
    arity: usize,
    constants: Box<[Constant<'gc>]>,
    code: Box<[Instruction]>,
}

#[derive(Collect)]
#[collect(no_drop)]
pub enum Constant<'gc> {
    Int(i64),
    Float(f64),
    String(StringPtr<'gc>),
}

#[derive(Collect)]
#[collect(no_drop)]
pub enum Instruction {}
