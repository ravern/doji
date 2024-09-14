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
    fiber::Fiber,
    gc::{Handle, Heap, Trace, Tracer},
};

macro_rules! define_float_op {
    ($name:ident, $op:tt, $res:ident) => {
        define_float_op!($name, $op, $res, $res);
    };
    ($name:ident, $op:tt, $res_int:ident, $res_float:ident) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, WrongTypeError> {
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
                (Value::Int(_), value) | (Value::Float(_), value) | (value, _) => Err(WrongTypeError {
                    expected: [ValueType::Int, ValueType::Float].into(),
                    found: value.ty(),
                }),
            }
        }
    };
}

macro_rules! define_int_op {
    ($name:ident, $op:tt) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, WrongTypeError> {
            match (self, other) {
                (Value::Int(left), Value::Int(right)) => Ok(Value::Int(left $op right)),
                (Value::Int(_), value) | (value, _) => Err(WrongTypeError {
                    expected: [ValueType::Int].into(),
                    found: value.ty(),
                }),
            }
        }
    };
}

macro_rules! define_bool_op {
    ($name:ident, $op:tt) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, WrongTypeError> {
            match (self, other) {
                (Value::Bool(left), Value::Bool(right)) => Ok(Value::Bool(*left $op *right)),
                (Value::Bool(_), value) | (value, _) => Err(WrongTypeError {
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
    List(List<'gc>),
    Map(Map<'gc>),
    Closure(Closure<'gc>),
    Fiber(Fiber<'gc>),
    // NativeFunction(NativeFunction),
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

    pub fn allocate_closure(heap: &Heap<'gc>, function: Function) -> Value<'gc> {
        Value::Closure(Closure::allocate(heap, function))
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

    pub fn eq(&self, other: &Value<'gc>) -> Result<Value<'gc>, WrongTypeError> {
        Ok(Value::Bool(self == other))
    }

    pub fn neg(&self) -> Result<Value<'gc>, WrongTypeError> {
        match self {
            Value::Int(value) => Ok(Value::Int(-value)),
            Value::Float(value) => Ok(Value::Float(Float::from(-value.into_f64()))),
            value => Err(WrongTypeError {
                expected: [ValueType::Int, ValueType::Float].into(),
                found: value.ty(),
            }),
        }
    }

    pub fn not(&self) -> Result<Value<'gc>, WrongTypeError> {
        match self {
            Value::Bool(value) => Ok(Value::Bool(!value)),
            value => Err(WrongTypeError {
                expected: [ValueType::Bool].into(),
                found: value.ty(),
            }),
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

impl<'gc> Closure<'gc> {
    pub fn allocate(heap: &Heap<'gc>, function: Function) -> Closure<'gc> {
        Closure {
            inner: heap
                .allocate(ClosureInner {
                    function,
                    upvalues: [].into(),
                })
                .as_handle(),
        }
    }

    pub fn arity(&self) -> u8 {
        self.inner.root().function.chunk.arity
    }
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
    pub fn new(chunk: Chunk) -> Function {
        Function {
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

// pub struct NativeFunction {
//     inner: Rc<NativeFunctionInner>,
// }

#[derive(Debug)]
pub struct WrongTypeError {
    pub expected: ValueTypes,
    pub found: ValueType,
}

impl Display for WrongTypeError {
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
        }
    }
}
