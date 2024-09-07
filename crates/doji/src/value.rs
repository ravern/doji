use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    rc::Rc,
};

use crate::{
    code::{Chunk, CodeOffset, Instruction},
    gc::{Handle, Trace, Tracer},
};

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(Float),
    String(String),
    List(List<'gc>),
    Map(Map<'gc>),
    Closure(Closure<'gc>),
}

impl<'gc> Trace<'gc> for Value<'gc> {
    fn trace(&self, tracer: &Tracer) {
        match self {
            Value::Nil | Value::Bool(_) | Value::Int(_) | Value::Float(_) | Value::String(_) => {}
            Value::List(list) => list.trace(tracer),
            Value::Map(map) => map.trace(tracer),
            Value::Closure(closure) => closure.trace(tracer),
        }
    }
}

// FIXME: Should we really be deriving PartialEq here?
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Float(f64);

impl Eq for Float {}

impl Hash for Float {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.to_bits().hash(state);
    }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct String(Box<str>);

#[derive(Debug)]
pub struct List<'gc>(Handle<'gc, Vec<Value<'gc>>>);

impl<'gc> Clone for List<'gc> {
    fn clone(&self) -> Self {
        List(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for List<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for List<'gc> {}

impl<'gc> Hash for List<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

impl<'gc> Trace<'gc> for List<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
pub struct Map<'gc>(Handle<'gc, HashMap<Value<'gc>, Value<'gc>>>);

impl<'gc> Clone for Map<'gc> {
    fn clone(&self) -> Self {
        Map(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for Map<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for Map<'gc> {}

impl<'gc> Hash for Map<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

impl<'gc> Trace<'gc> for Map<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
pub struct Closure<'gc>(Handle<'gc, ClosureInner<'gc>>);

impl<'gc> Clone for Closure<'gc> {
    fn clone(&self) -> Self {
        Closure(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for Closure<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for Closure<'gc> {}

impl<'gc> Hash for Closure<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

impl<'gc> Trace<'gc> for Closure<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
struct ClosureInner<'gc> {
    function: Function,
    upvalues: Box<[Upvalue<'gc>]>,
}

impl<'gc> Trace<'gc> for ClosureInner<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for upvalue in &*self.upvalues {
            upvalue.trace(tracer)
        }
    }
}

#[derive(Debug)]
pub struct Function {
    chunk: Rc<Chunk>,
}

impl Function {
    pub fn size(&self) -> usize {
        self.chunk.code.len()
    }

    pub fn instruction(&self, offset: CodeOffset) -> Option<Instruction> {
        self.chunk.code.get(offset.as_usize()).copied()
    }
}

impl Clone for Function {
    fn clone(&self) -> Self {
        Function {
            chunk: Rc::clone(&self.chunk),
        }
    }
}

#[derive(Debug)]
pub enum Upvalue<'gc> {
    Open(usize),
    Closed(Handle<'gc, Value<'gc>>),
}

impl<'gc> Trace<'gc> for Upvalue<'gc> {
    fn trace(&self, tracer: &Tracer) {
        match self {
            Upvalue::Open(_) => {}
            Upvalue::Closed(handle) => tracer.trace_handle(handle),
        }
    }
}
