use std::collections::HashMap;

use crate::gc::{Handle, Trace, Tracer};

pub enum Value<'gc> {
    Uninitialized,
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    Object(Handle<'gc, Object<'gc>>),
}

impl<'gc> Clone for Value<'gc> {
    fn clone(&self) -> Self {
        match self {
            Value::Uninitialized => Value::Uninitialized,
            Value::Nil => Value::Nil,
            Value::Bool(value) => Value::Bool(*value),
            Value::Int(value) => Value::Int(*value),
            Value::Float(value) => Value::Float(*value),
            Value::Object(handle) => Value::Object(Handle::clone(&handle)),
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

pub enum Object<'gc> {
    String(Box<str>),
    List(List<'gc>),
    Map(Map<'gc>),
}

impl<'gc> Trace<'gc> for Object<'gc> {
    fn trace(&self, tracer: &Tracer) {
        match self {
            Object::String(string) => string.trace(tracer),
            Object::List(list) => list.trace(tracer),
            Object::Map(map) => map.trace(tracer),
        }
    }
}

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
