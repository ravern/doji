use std::{
    cell::RefCell,
    collections::HashMap,
    fmt::{self, Display, Formatter},
    hash::{Hash, Hasher},
    rc::Rc,
};

use crate::{
    bytecode::{self, Arity, Chunk, Instruction, InstructionOffset, UpvalueIndex},
    env::Environment,
    error::Error,
    fiber::{AbsoluteStackSlot, FiberStack, FiberValue},
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
                (Value::Int(_), value) | (Value::Float(_), value) | (value, _) => Err(TypeError::new(
                    [ValueType::Int, ValueType::Float],
                    value.ty(),
                )),
            }
        }
    };
}

macro_rules! define_int_op {
    ($name:ident, $op:tt) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
            match (self, other) {
                (Value::Int(left), Value::Int(right)) => Ok(Value::Int(left $op right)),
                (Value::Int(_), value) | (value, _) => Err(TypeError::new(
                    [ValueType::Int],
                    value.ty(),
                )),
            }
        }
    };
}

macro_rules! define_bool_op {
    ($name:ident, $op:tt) => {
        pub fn $name(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
            match (self, other) {
                (Value::Bool(left), Value::Bool(right)) => Ok(Value::Bool(*left $op *right)),
                (Value::Bool(_), value) | (value, _) => Err(TypeError::new(
                    [ValueType::Bool],
                    value.ty(),
                )),
            }
        }
    };
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
pub enum Value<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(FloatValue),
    String(StringValue<'gc>),
    List(ListValue<'gc>),
    Map(MapValue<'gc>),
    Closure(ClosureValue<'gc>),
    Fiber(FiberValue<'gc>),
    NativeFunction(NativeFunctionValue),
}

impl<'gc> Value<'gc> {
    pub fn nil() -> Value<'gc> {
        Value::Nil
    }

    pub fn bool(bool: bool) -> Value<'gc> {
        Value::Bool(bool)
    }

    pub fn int(int: i64) -> Value<'gc> {
        Value::Int(int)
    }

    pub fn float(float: f64) -> Value<'gc> {
        Value::Float(FloatValue::from(float))
    }

    pub fn string_in(heap: &Heap<'gc>, string: String) -> Value<'gc> {
        Value::String(StringValue::new_in(heap, string))
    }

    pub fn list_in(heap: &Heap<'gc>) -> Value<'gc> {
        Value::List(ListValue::new_in(heap))
    }

    pub fn map_in(heap: &Heap<'gc>) -> Value<'gc> {
        Value::Map(MapValue::new_in(heap))
    }

    pub fn closure_in(
        heap: &Heap<'gc>,
        function: Function,
        upvalues: Box<[UpvalueHandle<'gc>]>,
    ) -> Value<'gc> {
        Value::Closure(ClosureValue::new_in(heap, function, upvalues))
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
    define_bool_op!(or, ||);
    define_int_op!(bit_and, &);
    define_int_op!(bit_or, |);
    define_int_op!(bit_xor, ^);

    pub fn eq(&self, other: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
        Ok(Value::Bool(self == other))
    }

    pub fn neg(&self) -> Result<Value<'gc>, TypeError> {
        match self {
            Value::Int(value) => Ok(Value::Int(-value)),
            Value::Float(value) => Ok(Value::Float(FloatValue::from(-value.into_f64()))),
            value => Err(TypeError::new(
                [ValueType::Int, ValueType::Float],
                value.ty(),
            )),
        }
    }

    pub fn not(&self) -> Result<Value<'gc>, TypeError> {
        match self {
            Value::Bool(value) => Ok(Value::Bool(!value)),
            value => Err(TypeError::new([ValueType::Bool], value.ty())),
        }
    }

    pub fn get(&self, key: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
        match self {
            Value::List(list) => list.get(key),
            Value::Map(map) => map.get(key),
            _ => Err(TypeError::new([ValueType::List, ValueType::Map], self.ty())),
        }
    }

    pub fn set(&self, key: Value<'gc>, value: Value<'gc>) -> Result<(), TypeError> {
        match self {
            Value::List(list) => list.set(key, value),
            Value::Map(map) => map.set(key, value),
            _ => Err(TypeError::new([ValueType::List, ValueType::Map], self.ty())),
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
            | Value::NativeFunction(_) => {}
            Value::String(string) => string.trace(tracer),
            Value::List(list) => list.trace(tracer),
            Value::Map(map) => map.trace(tracer),
            Value::Closure(closure) => closure.trace(tracer),
            Value::Fiber(fiber) => fiber.trace(tracer),
        }
    }
}

// FIXME: Should we really be deriving PartialEq here?
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FloatValue(f64);

impl FloatValue {
    pub fn into_f64(self) -> f64 {
        self.0
    }
}

impl From<f64> for FloatValue {
    fn from(value: f64) -> Self {
        FloatValue(value)
    }
}

impl Into<f64> for FloatValue {
    fn into(self) -> f64 {
        self.0
    }
}

impl Eq for FloatValue {}

impl Hash for FloatValue {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.to_bits().hash(state);
    }
}

#[derive(Debug)]
pub struct StringValue<'gc>(Handle<'gc, Box<str>>);

impl<'gc> StringValue<'gc> {
    pub fn new_in(heap: &Heap<'gc>, value: String) -> StringValue<'gc> {
        StringValue(heap.allocate(value.into_boxed_str()).as_handle())
    }
}

impl<'gc> Clone for StringValue<'gc> {
    fn clone(&self) -> Self {
        StringValue(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for StringValue<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0) || &*self.0.root() == &*other.0.root()
    }
}

impl<'gc> Eq for StringValue<'gc> {}

impl<'gc> Hash for StringValue<'gc> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Box::<str>::hash(&self.0.root(), state);
    }
}

impl<'gc> Trace<'gc> for StringValue<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

macro_rules! define_value {
    ($name:ident, $lt:lifetime, $data:ty) => {
        #[derive(Debug)]
        pub struct $name<$lt>(Handle<$lt, $data>);

        impl<$lt> Clone for $name<$lt> {
            fn clone(&self) -> Self {
                $name(Handle::clone(&self.0))
            }
        }

        impl<$lt> PartialEq for $name<$lt> {
            fn eq(&self, other: &Self) -> bool {
                Handle::ptr_eq(&self.0, &other.0)
            }
        }

        impl<$lt> Eq for $name<$lt> {}

        impl<$lt> Hash for $name<$lt> {
            fn hash<H: Hasher>(&self, state: &mut H) {
                Handle::as_ptr(&self.0).hash(state);
            }
        }

        impl<$lt> Trace<$lt> for $name<$lt> {
            fn trace(&self, tracer: &Tracer) {
                tracer.trace_handle(&self.0);
            }
        }
    };
}

define_value!(ListValue, 'gc, RefCell<Vec<Value<'gc>>>);

impl<'gc> ListValue<'gc> {
    pub fn new_in(heap: &Heap<'gc>) -> ListValue<'gc> {
        ListValue(heap.allocate(RefCell::new(Vec::new())).as_handle())
    }

    pub fn get(&self, index: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
        if let Value::Int(index) = index {
            Ok(self
                .0
                .root()
                .borrow()
                .get(*index as usize)
                .cloned()
                .unwrap_or(Value::Nil))
        } else {
            Err(TypeError::new([ValueType::Int], index.ty()))
        }
    }

    pub fn set(&self, index: Value<'gc>, value: Value<'gc>) -> Result<(), TypeError> {
        if let Value::Int(index) = index {
            let index = index as usize;
            let self_root = self.0.root();
            let mut self_ref = self_root.borrow_mut();
            // Resize if necessary
            if index >= self_ref.len() {
                self_ref.resize(index + 1, Value::Nil);
            }
            self_ref.insert(index, value);
            Ok(())
        } else {
            Err(TypeError::new([ValueType::Int], index.ty()))
        }
    }
}

define_value!(MapValue, 'gc, RefCell<HashMap<Value<'gc>, Value<'gc>>>);

impl<'gc> MapValue<'gc> {
    pub fn new_in(heap: &Heap<'gc>) -> MapValue<'gc> {
        MapValue(heap.allocate(RefCell::new(HashMap::new())).as_handle())
    }

    pub fn get(&self, key: &Value<'gc>) -> Result<Value<'gc>, TypeError> {
        Ok(self
            .0
            .root()
            .borrow()
            .get(key)
            .cloned()
            .unwrap_or(Value::Nil))
    }

    pub fn set(&self, key: Value<'gc>, value: Value<'gc>) -> Result<(), TypeError> {
        self.0.root().borrow_mut().insert(key, value);
        Ok(())
    }
}

define_value!(ClosureValue, 'gc, Closure<'gc>);

impl<'gc> ClosureValue<'gc> {
    pub fn new_in(
        heap: &Heap<'gc>,
        function: Function,
        upvalues: Box<[UpvalueHandle<'gc>]>,
    ) -> ClosureValue<'gc> {
        ClosureValue(heap.allocate(Closure { function, upvalues }).as_handle())
    }

    pub fn function(&self) -> Function {
        self.0.root().function.clone()
    }

    pub fn arity(&self) -> Arity {
        self.0.root().function.arity()
    }

    pub fn upvalue(&self, index: UpvalueIndex) -> Option<UpvalueHandle<'gc>> {
        self.0.root().upvalues.get(index.into_usize()).cloned()
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
pub struct Function(Rc<Chunk>);

impl Function {
    pub fn new(chunk: Chunk) -> Function {
        Function(Rc::new(chunk))
    }

    pub fn arity(&self) -> Arity {
        self.0.arity
    }

    pub fn size(&self) -> usize {
        self.0.instructions.len()
    }

    pub fn upvalues(&self) -> &[bytecode::Upvalue] {
        &self.0.upvalues
    }

    pub fn instruction(&self, offset: InstructionOffset) -> Option<Instruction> {
        self.0.instructions.get(offset.into_usize()).copied()
    }
}

impl Clone for Function {
    fn clone(&self) -> Self {
        Function(Rc::clone(&self.0))
    }
}

#[derive(Debug)]
pub struct UpvalueHandle<'gc>(Handle<'gc, RefCell<Upvalue<'gc>>>);

impl<'gc> UpvalueHandle<'gc> {
    pub fn new_in(heap: &Heap<'gc>, slot: AbsoluteStackSlot) -> UpvalueHandle<'gc> {
        UpvalueHandle(heap.allocate(RefCell::new(Upvalue::Open(slot))).as_handle())
    }

    pub fn slot(&self) -> Option<AbsoluteStackSlot> {
        match &*self.0.root().borrow() {
            Upvalue::Open(slot) => Some(*slot),
            Upvalue::Closed(_) => None,
        }
    }

    pub fn get_in(&self, stack: &FiberStack<'gc>) -> Option<Value<'gc>> {
        match &*self.0.root().borrow() {
            Upvalue::Open(slot) => stack.get_absolute(*slot),
            Upvalue::Closed(value) => Some(value.clone()),
        }
    }

    pub fn set_in(&self, stack: &mut FiberStack<'gc>, value: Value<'gc>) {
        match &mut *self.0.root().borrow_mut() {
            Upvalue::Open(slot) => {
                stack.set_absolute(*slot, value);
            }
            Upvalue::Closed(upvalue_value) => *upvalue_value = value,
        }
    }

    pub fn close_in(&self, stack: &FiberStack<'gc>) {
        let value = self.get_in(stack).unwrap();
        *self.0.root().borrow_mut() = Upvalue::Closed(value);
    }
}

impl<'gc> Clone for UpvalueHandle<'gc> {
    fn clone(&self) -> Self {
        UpvalueHandle(Handle::clone(&self.0))
    }
}

impl<'gc> Trace<'gc> for UpvalueHandle<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

#[derive(Debug)]
pub enum Upvalue<'gc> {
    Open(AbsoluteStackSlot),
    Closed(Value<'gc>),
}

impl<'gc> Trace<'gc> for Upvalue<'gc> {
    fn trace(&self, tracer: &Tracer) {
        match self {
            Upvalue::Open(_) => {}
            Upvalue::Closed(value) => value.trace(tracer),
        }
    }
}

#[derive(Debug)]
pub struct NativeFunctionValue(Rc<NativeFunction>);

impl NativeFunctionValue {
    pub fn new(arity: Arity, function: NativeFunctionFn) -> NativeFunctionValue {
        NativeFunctionValue(Rc::new(NativeFunction { arity, function }))
    }

    pub fn arity(&self) -> Arity {
        self.0.arity
    }

    pub fn call<'gc>(
        &self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
        stack: &mut FiberStack<'gc>,
    ) -> Result<(), Error> {
        (self.0.function)(env, heap, stack)
    }
}

impl Clone for NativeFunctionValue {
    fn clone(&self) -> Self {
        NativeFunctionValue(Rc::clone(&self.0))
    }
}

impl PartialEq for NativeFunctionValue {
    fn eq(&self, other: &Self) -> bool {
        Rc::ptr_eq(&self.0, &other.0)
    }
}

impl Eq for NativeFunctionValue {}

impl Hash for NativeFunctionValue {
    fn hash<H: Hasher>(&self, state: &mut H) {
        Rc::as_ptr(&self.0).hash(state);
    }
}

pub type NativeFunctionFn =
    for<'gc> fn(&Environment<'gc>, &Heap<'gc>, &mut FiberStack<'gc>) -> Result<(), Error>;

#[derive(Debug)]
struct NativeFunction {
    arity: Arity,
    function: NativeFunctionFn,
}

#[derive(Debug)]
pub struct TypeError {
    pub expected: ValueTypes,
    pub found: ValueType,
}

impl TypeError {
    pub fn new<V>(expected: V, found: ValueType) -> TypeError
    where
        V: Into<ValueTypes>,
    {
        TypeError {
            expected: expected.into(),
            found,
        }
    }
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

impl<T> From<T> for ValueTypes
where
    T: IntoIterator<Item = ValueType>,
{
    fn from(types: T) -> ValueTypes {
        ValueTypes(types.into_iter().collect())
    }
}

impl Display for ValueTypes {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        self.0
            .iter()
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
