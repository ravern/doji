use std::{
    cell::RefCell,
    collections::HashMap,
    time::{Duration, Instant},
};

use generational_arena::Index;

use crate::{context::Context, value::Value};

#[derive(Default)]
pub struct Driver {
    ops: RefCell<HashMap<Id, (Instant, u64)>>,
}

impl Driver {
    pub fn dispatch<'gc>(&self, cx: &Context<'gc>, id: Id, op: Value<'gc>) {
        let duration = op.try_into::<i64>(cx).unwrap();
        if duration < 0 {
            panic!("duration cannot be negative");
        }
        self.ops
            .borrow_mut()
            .insert(id, (Instant::now(), duration as u64));
    }

    pub fn poll<'gc>(&self, cx: &Context<'gc>) -> Option<(Id, Value<'gc>)> {
        let now = Instant::now();
        let ops = self.ops.borrow();
        let entry = ops.iter().find(|(_, (start_time, duration))| {
            now - *start_time >= Duration::from_millis(*duration)
        });
        let (id, duration) = if let Some((id, (_, duration))) = entry {
            (*id, *duration)
        } else {
            return None;
        };
        drop(ops);
        self.ops.borrow_mut().remove(&id);
        Some((id, (duration as i64).into()))
    }
}

#[derive(Clone, Copy, Eq, Hash, PartialEq)]
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
