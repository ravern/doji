use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    mem,
    rc::Rc,
};

use crate::{
    code::Function,
    gc::{Handle, Trace, Tracer},
};

#[derive(Debug)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(Float),
    Object(Handle<'gc, Object<'gc>>),
}

impl<'gc> Clone for Value<'gc> {
    fn clone(&self) -> Self {
        match self {
            Value::Nil => Value::Nil,
            Value::Bool(value) => Value::Bool(*value),
            Value::Int(value) => Value::Int(*value),
            Value::Float(value) => Value::Float(*value),
            Value::Object(handle) => Value::Object(Handle::clone(&handle)),
        }
    }
}

impl<'gc> Eq for Value<'gc> {}

impl<'gc> Hash for Value<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        mem::discriminant(self).hash(state);
        match self {
            Value::Nil => 0.hash(state),
            Value::Bool(value) => value.hash(state),
            Value::Int(value) => value.hash(state),
            Value::Float(value) => value.hash(state),
            Value::Object(handle) => Handle::as_ptr(handle).hash(state),
        }
    }
}

impl<'gc> PartialEq for Value<'gc> {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Value::Nil, Value::Nil) => true,
            (Value::Bool(left), Value::Bool(right)) => left == right,
            (Value::Int(left), Value::Int(right)) => left == right,
            (Value::Float(left), Value::Float(right)) => left == right,
            (Value::Object(left), Value::Object(right)) => Handle::ptr_eq(left, right),
            _ => false,
        }
    }
}

impl<'gc> Trace<'gc> for Value<'gc> {
    fn trace(&self, tracer: &Tracer) {
        if let Value::Object(handle) = self {
            tracer.trace_handle(handle);
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Float(f64);

impl Eq for Float {}

impl Hash for Float {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.to_bits().hash(state);
    }
}

#[derive(Debug)]
pub enum Object<'gc> {
    String(String),
    List(List<'gc>),
    Map(Map<'gc>),
    Closure(Closure<'gc>),
}

impl<'gc> Trace<'gc> for Object<'gc> {
    fn trace(&self, tracer: &Tracer) {
        match self {
            Object::String(string) => string.trace(tracer),
            Object::List(list) => list.trace(tracer),
            Object::Map(map) => map.trace(tracer),
            Object::Closure(closure) => closure.trace(tracer),
        }
    }
}

#[derive(Debug)]
pub struct List<'gc> {
    items: Vec<Value<'gc>>,
}

impl<'gc> Trace<'gc> for List<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for item in &self.items {
            item.trace(tracer);
        }
    }
}

#[derive(Debug)]
pub struct Map<'gc> {
    items: HashMap<Value<'gc>, Value<'gc>>,
}

impl<'gc> Trace<'gc> for Map<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for (key, value) in &self.items {
            key.trace(tracer);
            value.trace(tracer);
        }
    }
}

#[derive(Debug)]
pub struct Closure<'gc> {
    function: Rc<Function>,
    upvalues: Box<[Upvalue<'gc>]>,
}

impl<'gc> Trace<'gc> for Closure<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for upvalue in &*self.upvalues {
            upvalue.trace(tracer)
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
