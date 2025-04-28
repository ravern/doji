use std::fmt::{self, Display, Formatter};

use gc_arena::{Collect, Gc};

use crate::context::Context;

pub type StringPtr<'gc> = Gc<'gc, StringValue>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct StringValue(String);

impl<'gc> StringValue {
    pub fn new_ptr(cx: &Context<'gc>, string: String) -> StringPtr<'gc> {
        Gc::new(cx.mutation(), StringValue(string))
    }
}

impl<'gc> Display for StringValue {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}
