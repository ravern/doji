use crate::{code::Function, value::Value};

pub struct Environment<'gc> {
    pub values: ValuePool<'gc>,
    pub functions: FunctionPool,
}

pub struct ValuePool<'gc> {
    values: Vec<Value<'gc>>,
}

pub struct FunctionPool {
    functions: Vec<Function>,
}
