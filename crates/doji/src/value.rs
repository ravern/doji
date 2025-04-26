use crate::{function::FunctionPtr, string::StringPtr};

pub struct Value<'gc>(ValueInner<'gc>);

enum ValueInner<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    String(StringPtr<'gc>),
}
