use std::{
    collections::HashMap,
    fmt,
    hash::{Hash, Hasher},
    mem,
};

use doji_program::Constant;

use crate::gc::{Handle, Heap, Trace, Tracer};

#[derive(Debug, PartialEq)]
pub enum ValueType {
    Nil,
    Bool,
    Int,
    Float,
    String,
    List,
    Map,
    Closure,
    Fiber,
}

impl fmt::Display for ValueType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ValueType::Nil => write!(f, "nil"),
            ValueType::Bool => write!(f, "bool"),
            ValueType::Int => write!(f, "int"),
            ValueType::Float => write!(f, "float"),
            ValueType::String => write!(f, "string"),
            ValueType::List => write!(f, "list"),
            ValueType::Map => write!(f, "map"),
            ValueType::Closure => write!(f, "closure"),
            ValueType::Fiber => write!(f, "fiber"),
        }
    }
}

#[derive(Debug)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    Object(Handle<'gc, Object<'gc>>),
}

impl<'gc> Value<'gc> {
    pub fn from_constant(constant: Constant, heap: &Heap<'gc>) -> Value<'gc> {
        match constant {
            Constant::Int(value) => Value::Int(value),
            Constant::Float(value) => Value::Float(value),
            Constant::String(string) => {
                Value::Object(heap.allocate(Object::String(string)).as_handle())
            }
        }
    }

    pub fn ty(&self) -> ValueType {
        match self {
            Value::Nil => ValueType::Nil,
            Value::Bool(_) => ValueType::Bool,
            Value::Int(_) => ValueType::Int,
            Value::Float(_) => ValueType::Float,
            Value::Object(handle) => match &*handle.root() {
                Object::String(_) => ValueType::String,
                Object::List(_) => ValueType::List,
                Object::Map(_) => ValueType::Map,
            },
        }
    }
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
        mem::discriminant(&self).hash(state);
        match self {
            Value::Nil => 0.hash(state),
            Value::Bool(value) => value.hash(state),
            Value::Int(value) => value.hash(state),
            Value::Float(value) => value.to_bits().hash(state),
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

#[derive(Debug)]
pub enum Object<'gc> {
    String(Box<str>),
    List(List<'gc>),
    Map(Map<'gc>),
}

impl<'gc> PartialEq for Object<'gc> {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Object::String(left), Object::String(right)) => left == right,
            (Object::List(left), Object::List(right)) => left == right,
            (Object::Map(left), Object::Map(right)) => left == right,
            _ => false,
        }
    }
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

#[derive(Debug)]
pub struct List<'gc> {
    items: Vec<Value<'gc>>,
}

impl<'gc> PartialEq for List<'gc> {
    fn eq(&self, other: &Self) -> bool {
        self.items == other.items
    }
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

impl<'gc> PartialEq for Map<'gc> {
    fn eq(&self, other: &Self) -> bool {
        self.items == other.items
    }
}

impl<'gc> Trace<'gc> for Map<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for (key, value) in &self.items {
            key.trace(tracer);
            value.trace(tracer);
        }
    }
}
