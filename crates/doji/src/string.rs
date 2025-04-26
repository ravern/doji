use alloc::string::String;
use gc_arena::Gc;

pub type StringPtr<'gc> = Gc<'gc, String>;
