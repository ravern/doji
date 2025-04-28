use gc_arena::Gc;

pub type StringPtr<'gc> = Gc<'gc, String>;
