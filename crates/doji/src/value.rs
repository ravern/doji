use std::{
    cell::RefCell,
    collections::HashMap,
    fmt::{self, Display, Formatter},
    hash::{Hash, Hasher},
    rc::Rc,
};

use crate::{
    code::{Chunk, CodeOffset, Instruction},
    env::Environment,
    error::Error,
    fiber::{FiberHandle, Stack},
    gc::{Handle, Heap, Trace, Tracer},
};

macro_rules! define_float_op {
    ($name:ident, $op:tt, $res:ident) => {
        define_float_op!($name, $op, $res, $res);
    };
    ($name:ident, $op:tt, $res_int:ident, $res_float:ident) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
            match (self, other) {
                (Value::Int(left), Value::Int(right)) => Ok(Value::$res_int(left $op right)),
                (Value::Int(left), Value::Float(right)) => {
                    let result = (*left as f64) $op right.into_f64();
                    Ok(Value::$res_float(result.into()))
                }
                (Value::Float(left), Value::Int(right)) => {
                    let result = left.into_f64() $op (*right as f64);
                    Ok(Value::$res_float(result.into()))
                }
                (Value::Float(left), Value::Float(right)) => {
                    let result = left.into_f64() $op right.into_f64();
                    Ok(Value::$res_float(result.into()))
                }
                (Value::Int(_), value) | (Value::Float(_), value) | (value, _) => Err(TypeError {
                    expected: [ValueType::Int, ValueType::Float].into(),
                    found: value.ty(),
                }),
            }
        }
    };
}

macro_rules! define_int_op {
    ($name:ident, $op:tt) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
            match (self, other) {
                (Value::Int(left), Value::Int(right)) => Ok(Value::Int(left $op right)),
                (Value::Int(_), value) | (value, _) => Err(TypeError {
                    expected: [ValueType::Int].into(),
                    found: value.ty(),
                }),
            }
        }
    };
}

macro_rules! define_bool_op {
    ($name:ident, $op:tt) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
            match (self, other) {
                (Value::Bool(left), Value::Bool(right)) => Ok(Value::Bool(*left $op *right)),
                (Value::Bool(_), value) | (value, _) => Err(TypeError {
                    expected: [ValueType::Bool].into(),
                    found: value.ty(),
                }),
            }
        }
    };
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(Float),
    String(String),
    List(ListHandle<'gc>),
    Map(MapHandle<'gc>),
    Closure(ClosureHandle<'gc>),
    Fiber(FiberHandle<'gc>),
    NativeFunction(NativeFunctionHandle),
}

impl<'gc> Value<'gc> {
    pub fn float(value: f64) -> Value<'gc> {
        Value::Float(Float::from(value))
    }

    pub fn list_in(heap: &Heap<'gc>) -> Value<'gc> {
        Value::List(ListHandle::new_in(heap))
    }

    pub fn map_in(heap: &Heap<'gc>) -> Value<'gc> {
        Value::Map(MapHandle::new_in(heap))
    }

    pub fn closure_in(heap: &Heap<'gc>, function: Function) -> Value<'gc> {
        Value::Closure(ClosureHandle::new_in(heap, function))
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
            Value::Fiber(_) => ValueType::Fiber,
            Value::NativeFunction(_) => ValueType::NativeFunction,
        }
    }

    define_float_op!(add, +, Int, Float);
    define_float_op!(sub, -, Int, Float);
    define_float_op!(mul, *, Int, Float);
    define_float_op!(div, /, Int, Float);
    define_int_op!(rem, %);
    define_float_op!(gt, >, Bool);
    define_float_op!(gte, >=, Bool);
    define_float_op!(lt, <, Bool);
    define_float_op!(lte, <=, Bool);
    define_bool_op!(and, &&);
    define_bool_op!(or, &&);
    define_int_op!(bit_and, &);
    define_int_op!(bit_or, |);
    define_int_op!(bit_xor, ^);

    pub fn eq(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
        Ok(Value::Bool(self == other))
    }

    pub fn neg(&self) -> Result<Value<'gc>, TypeError> {
        match self {
            Value::Int(value) => Ok(Value::Int(-value)),
            Value::Float(value) => Ok(Value::Float(Float::from(-value.into_f64()))),
            value => Err(TypeError {
                expected: [ValueType::Int, ValueType::Float].into(),
                found: value.ty(),
            }),
        }
    }

    pub fn not(&self) -> Result<Value<'gc>, TypeError> {
        match self {
            Value::Bool(value) => Ok(Value::Bool(!value)),
            value => Err(TypeError {
                expected: [ValueType::Bool].into(),
                found: value.ty(),
            }),
        }
    }
}

impl<'gc> Trace<'gc> for Value<'gc> {
    fn trace(&self, tracer: &Tracer) {
        match self {
            Value::Nil
            | Value::Bool(_)
            | Value::Int(_)
            | Value::Float(_)
            | Value::String(_)
            | Value::NativeFunction(_) => {}
            Value::List(list) => list.trace(tracer),
            Value::Map(map) => map.trace(tracer),
            Value::Closure(closure) => closure.trace(tracer),
            Value::Fiber(fiber) => fiber.trace(tracer),
        }
    }
}

// FIXME: Should we really be deriving PartialEq here?
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Float(f64);

impl Float {
    pub fn into_f64(self) -> f64 {
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
pub struct ListHandle<'gc>(Handle<'gc, RefCell<Vec<Value<'gc>>>>);

impl<'gc> ListHandle<'gc> {
    pub fn new_in(heap: &Heap<'gc>) -> ListHandle<'gc> {
        ListHandle(heap.allocate(RefCell::new(Vec::new())).as_handle())
    }
}

impl<'gc> Clone for ListHandle<'gc> {
    fn clone(&self) -> Self {
        ListHandle(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for ListHandle<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for ListHandle<'gc> {}

impl<'gc> Hash for ListHandle<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

impl<'gc> Trace<'gc> for ListHandle<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
pub struct MapHandle<'gc>(Handle<'gc, RefCell<HashMap<Value<'gc>, Value<'gc>>>>);

impl<'gc> MapHandle<'gc> {
    pub fn new_in(heap: &Heap<'gc>) -> MapHandle<'gc> {
        MapHandle(heap.allocate(RefCell::new(HashMap::new())).as_handle())
    }
}

impl<'gc> Clone for MapHandle<'gc> {
    fn clone(&self) -> Self {
        MapHandle(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for MapHandle<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for MapHandle<'gc> {}

impl<'gc> Hash for MapHandle<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

impl<'gc> Trace<'gc> for MapHandle<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
pub struct ClosureHandle<'gc>(Handle<'gc, Closure<'gc>>);

impl<'gc> ClosureHandle<'gc> {
    pub fn new_in(heap: &Heap<'gc>, function: Function) -> ClosureHandle<'gc> {
        ClosureHandle(
            heap.allocate(Closure {
                function,
                upvalues: [].into(),
            })
            .as_handle(),
        )
    }

    pub fn function(&self) -> Function {
        self.0.root().function.clone()
    }

    pub fn arity(&self) -> u8 {
        self.0.root().function.arity
    }
}

impl<'gc> Clone for ClosureHandle<'gc> {
    fn clone(&self) -> Self {
        ClosureHandle(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for ClosureHandle<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for ClosureHandle<'gc> {}

impl<'gc> Hash for ClosureHandle<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

impl<'gc> Trace<'gc> for ClosureHandle<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
struct Closure<'gc> {
    function: Function,
    upvalues: Box<[UpvalueHandle<'gc>]>,
}

impl<'gc> Trace<'gc> for Closure<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for upvalue in &*self.upvalues {
            upvalue.trace(tracer)
        }
    }
}

#[derive(Debug)]
pub struct Function {
    arity: u8,
    chunk: Rc<Chunk>,
}

impl Function {
    pub fn new(arity: u8, chunk: Chunk) -> Function {
        Function {
            arity,
            chunk: Rc::new(chunk),
        }
    }

    pub fn size(&self) -> usize {
        self.chunk.code.len()
    }

    pub fn instruction(&self, offset: CodeOffset) -> Option<Instruction> {
        self.chunk.code.get(offset.into_usize()).copied()
    }
}

impl Clone for Function {
    fn clone(&self) -> Self {
        Function {
            arity: self.arity,
            chunk: Rc::clone(&self.chunk),
        }
    }
}

#[derive(Debug)]
pub struct UpvalueHandle<'gc>(Handle<'gc, RefCell<Upvalue<'gc>>>);

impl<'gc> Trace<'gc> for UpvalueHandle<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
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

pub type NativeFunctionFn =
    for<'gc> fn(&Environment<'gc>, &Heap<'gc>, &mut Stack<'gc>) -> Result<(), Error>;

#[derive(Debug)]
pub struct NativeFunctionHandle(Rc<NativeFunction>);

impl NativeFunctionHandle {
    pub fn new(arity: u8, function: NativeFunctionFn) -> NativeFunctionHandle {
        NativeFunctionHandle(Rc::new(NativeFunction { arity, function }))
    }

    pub fn arity(&self) -> u8 {
        self.0.arity
    }

    pub fn call<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        stack: &mut Stack<'gc>,
    ) -> Result<(), Error> {
        (self.0.function)(env, heap, stack)
    }
}

impl Clone for NativeFunctionHandle {
    fn clone(&self) -> Self {
        NativeFunctionHandle(Rc::clone(&self.0))
    }
}

impl PartialEq for NativeFunctionHandle {
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }
}

impl Eq for NativeFunctionHandle {}

impl Hash for NativeFunctionHandle {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Rc::as_ptr(&self.0).hash(state);
    }
}

#[derive(Debug)]
struct NativeFunction {
    arity: u8,
    function: NativeFunctionFn,
}

#[derive(Debug)]
pub struct TypeError {
    pub expected: ValueTypes,
    pub found: ValueType,
}

impl Display for TypeError {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        write!(
            f,
            "wrong type: expected one of {}, found {}",
            self.expected, self.found
        )
    }
}

#[derive(Debug)]
pub struct ValueTypes(Box<[ValueType]>);

impl<const N: usize> From<[ValueType; N]> for ValueTypes {
    fn from(types: [ValueType; N]) -> ValueTypes {
        ValueTypes(types.into())
    }
}

impl Display for ValueTypes {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        self.0
            .into_iter()
            .map(ToString::to_string)
            .collect::<Box<[_]>>()
            .join(", ")
            .fmt(f)
    }
}

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
    Fiber,
    NativeFunction,
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
            ValueType::Fiber => write!(f, "fiber"),
            ValueType::NativeFunction => write!(f, "native function"),
        }
    }
}
