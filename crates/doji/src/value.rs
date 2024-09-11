use std::{
    cell::RefCell,
    collections::HashMap,
    fmt::{self, Display, Formatter},
    hash::{Hash, Hasher},
    rc::Rc,
};

use crate::{
    code::{Chunk, CodeOffset, Instruction},
    gc::{Handle, Heap, Trace, Tracer},
};

#[derive(Clone, Debug)]
pub enum ValueType {
    Nil,
    Bool,
    Int,
    Float,
    String,
    List,
    Map,
    Closure,
}

impl Display for ValueType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            ValueType::Nil => write!(f, "nil"),
            ValueType::Bool => write!(f, "bool"),
            ValueType::Int => write!(f, "int"),
            ValueType::Float => write!(f, "float"),
            ValueType::String => write!(f, "string"),
            ValueType::List => write!(f, "list"),
            ValueType::Map => write!(f, "map"),
            ValueType::Closure => write!(f, "closure"),
        }
    }
}

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

impl<'gc> Value<'gc> {
    pub fn float(value: f64) -> Value<'gc> {
        Value::Float(Float::from(value))
    }

    pub fn allocate_list(heap: &Heap<'gc>) -> Value<'gc> {
        Value::List(List::allocate(heap))
    }

    pub fn allocate_map(heap: &Heap<'gc>) -> Value<'gc> {
        Value::Map(Map::allocate(heap))
    }

    pub fn ty(&self) -> ValueType {
        match self {
            Value::Nil => ValueType::Nil,
            Value::Bool(_) => ValueType::Bool,
            Value::Int(_) => ValueType::Int,
            Value::Float(_) => ValueType::Float,
            Value::String(_) => ValueType::String,
            Value::List(_) => ValueType::List,
            Value::Map(_) => ValueType::Map,
            Value::Closure(_) => ValueType::Closure,
        }
    }
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

impl Float {
    pub fn from_f64(value: f64) -> Float {
        Float(value)
    }

    pub fn as_f64(self) -> f64 {
        self.0
    }
}

impl From<f64> for Float {
    fn from(value: f64) -> Self {
        Float(value)
    }
}

impl Into<f64> for Float {
    fn into(self) -> f64 {
        self.0
    }
}

impl Eq for Float {}

impl Hash for Float {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.to_bits().hash(state);
    }
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub struct String(Box<str>);

#[derive(Debug)]
pub struct List<'gc> {
    inner: Handle<'gc, RefCell<Vec<Value<'gc>>>>,
}

impl<'gc> List<'gc> {
    pub fn allocate(heap: &Heap<'gc>) -> List<'gc> {
        List {
            inner: heap.allocate(RefCell::new(Vec::new())).as_handle(),
        }
    }
}

impl<'gc> Clone for List<'gc> {
    fn clone(&self) -> Self {
        List {
            inner: Handle::clone(&self.inner),
        }
    }
}

impl<'gc> PartialEq for List<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.inner, &other.inner)
    }
}

impl<'gc> Eq for List<'gc> {}

impl<'gc> Hash for List<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.inner).hash(state);
    }
}

impl<'gc> Trace<'gc> for List<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.inner);
    }
}

#[derive(Debug)]
pub struct Map<'gc> {
    inner: Handle<'gc, RefCell<HashMap<Value<'gc>, Value<'gc>>>>,
}

impl<'gc> Map<'gc> {
    pub fn allocate(heap: &Heap<'gc>) -> Map<'gc> {
        Map {
            inner: heap.allocate(RefCell::new(HashMap::new())).as_handle(),
        }
    }
}

impl<'gc> Clone for Map<'gc> {
    fn clone(&self) -> Self {
        Map {
            inner: Handle::clone(&self.inner),
        }
    }
}

impl<'gc> PartialEq for Map<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.inner, &other.inner)
    }
}

impl<'gc> Eq for Map<'gc> {}

impl<'gc> Hash for Map<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.inner).hash(state);
    }
}

impl<'gc> Trace<'gc> for Map<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.inner);
    }
}

#[derive(Debug)]
pub struct Closure<'gc> {
    inner: Handle<'gc, ClosureInner<'gc>>,
}

impl<'gc> Clone for Closure<'gc> {
    fn clone(&self) -> Self {
        Closure {
            inner: Handle::clone(&self.inner),
        }
    }
}

impl<'gc> PartialEq for Closure<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.inner, &other.inner)
    }
}

impl<'gc> Eq for Closure<'gc> {}

impl<'gc> Hash for Closure<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.inner).hash(state);
    }
}

impl<'gc> Trace<'gc> for Closure<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.inner);
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
