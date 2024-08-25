use std::cell::RefCell;

use super::Tracer;

pub trait Trace<'gc>: 'gc {
    fn trace(&self, tracer: &Tracer);
}

impl<'gc> Trace<'gc> for Box<str> {
    fn trace(&self, _tracer: &Tracer) {}
}

impl<'gc> Trace<'gc> for String {
    fn trace(&self, _tracer: &Tracer) {}
}

impl<'gc, T> Trace<'gc> for RefCell<T>
where
    T: Trace<'gc>,
{
    fn trace(&self, tracer: &Tracer) {
        self.borrow().trace(tracer);
    }
}

impl<'gc, T> Trace<'gc> for Option<T>
where
    T: Trace<'gc>,
{
    fn trace(&self, tracer: &Tracer) {
        if let Some(value) = self {
            value.trace(tracer);
        }
    }
}
