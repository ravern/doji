use gc_arena::Gc;

pub(crate) type StringPtr<'gc> = Gc<'gc, String>;
