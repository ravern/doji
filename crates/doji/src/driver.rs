use generational_arena::Index;

use crate::{context::Context, value::Value};

#[derive(Default)]
pub struct Driver {}

impl Driver {
    pub fn dispatch<'gc>(&self, cx: &Context<'gc>, id: Id, op: Value<'gc>) {
        todo!()
    }

    pub fn poll<'gc>(&self, cx: &Context<'gc>) -> Option<(Id, Value<'gc>)> {
        todo!()
    }
}

#[derive(Clone, Copy)]
pub struct Id(Index);

impl From<Index> for Id {
    fn from(index: Index) -> Self {
        Self(index)
    }
}

impl From<Id> for Index {
    fn from(id: Id) -> Self {
        id.0
    }
}
