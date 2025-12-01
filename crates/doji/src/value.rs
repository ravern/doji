use core::fmt::{self, Display, Formatter};

use gc_arena::Collect;

use crate::{
    closure::ClosurePtr,
    context::Context,
    error::{ErrorPtr, ErrorValue},
    fiber::FiberPtr,
    string::{StringPtr, StringValue},
};

#[derive(Debug)]
pub enum ValueType {
    Nil,
    Bool,
    Int,
    Float,
    String,
    Closure,
    Fiber,
    Error,
}

impl Display for ValueType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::Nil => write!(f, "nil"),
            Self::Bool => write!(f, "bool"),
            Self::Int => write!(f, "int"),
            Self::Float => write!(f, "float"),
            Self::String => write!(f, "string"),
            Self::Closure => write!(f, "closure"),
            Self::Fiber => write!(f, "fiber"),
            Self::Error => write!(f, "error"),
        }
    }
}

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct Value<'gc>(ValueInner<'gc>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
enum ValueInner<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    String(StringPtr<'gc>),
    Closure(ClosurePtr<'gc>),
    Fiber(FiberPtr<'gc>),
    Error(ErrorPtr<'gc>),
}

impl<'gc> Value<'gc> {
    pub const NIL: Self = Self(ValueInner::Nil);
    pub const TRUE: Self = Self(ValueInner::Bool(true));
    pub const FALSE: Self = Self(ValueInner::Bool(false));

    pub fn ty(&self) -> ValueType {
        match self.0 {
            ValueInner::Nil => ValueType::Nil,
            ValueInner::Bool(_) => ValueType::Bool,
            ValueInner::Int(_) => ValueType::Int,
            ValueInner::Float(_) => ValueType::Float,
            ValueInner::String(_) => ValueType::String,
            ValueInner::Closure(_) => ValueType::Closure,
            ValueInner::Fiber(_) => ValueType::Fiber,
            ValueInner::Error(_) => ValueType::Error,
        }
    }

    pub fn try_into<T>(self, cx: &Context<'gc>) -> Result<T, ErrorPtr<'gc>>
    where
        T: TryFromValue<'gc>,
    {
        T::try_from_value(self, cx)
    }
}

impl<'gc> Default for Value<'gc> {
    fn default() -> Self {
        Self::NIL
    }
}

macro_rules! impl_from_for_value {
    ($ty:ty, $variant:ident) => {
        impl<'gc> From<$ty> for Value<'gc> {
            fn from(value: $ty) -> Self {
                Value(ValueInner::$variant(value))
            }
        }
    };
}

impl_from_for_value!(bool, Bool);
impl_from_for_value!(i64, Int);
impl_from_for_value!(f64, Float);
impl_from_for_value!(StringPtr<'gc>, String);
impl_from_for_value!(ClosurePtr<'gc>, Closure);
impl_from_for_value!(FiberPtr<'gc>, Fiber);
impl_from_for_value!(ErrorPtr<'gc>, Error);

pub trait TryFromValue<'gc>: Sized {
    fn try_from_value(value: Value<'gc>, cx: &Context<'gc>) -> Result<Self, ErrorPtr<'gc>>;
}

macro_rules! impl_try_from_value {
    ($ty:ty, $variant:ident, $expected:expr) => {
        impl<'gc> TryFromValue<'gc> for $ty {
            fn try_from_value(value: Value<'gc>, cx: &Context<'gc>) -> Result<Self, ErrorPtr<'gc>> {
                match value.0 {
                    ValueInner::$variant(v) => Ok(v),
                    _ => Err(ErrorValue::new_ptr(
                        cx,
                        StringValue::new_ptr(
                            cx,
                            format!("tried to convert {} to {}", value.ty(), $expected),
                        ),
                        value,
                    )),
                }
            }
        }
    };
}

impl_try_from_value!(bool, Bool, ValueType::Bool);
impl_try_from_value!(i64, Int, ValueType::Int);
impl_try_from_value!(f64, Float, ValueType::Float);
impl_try_from_value!(ClosurePtr<'gc>, Closure, ValueType::Closure);
impl_try_from_value!(FiberPtr<'gc>, Fiber, ValueType::Fiber);
impl_try_from_value!(ErrorPtr<'gc>, Error, ValueType::Error);

pub trait IntoValue<'gc>: Sized {
    fn into_value(self, cx: &Context<'gc>) -> Value<'gc>;
}

impl<'gc, T> IntoValue<'gc> for T
where
    T: Into<Value<'gc>>,
{
    fn into_value(self, _cx: &Context<'gc>) -> Value<'gc> {
        self.into()
    }
}

impl<'gc> IntoValue<'gc> for &str {
    fn into_value(self, cx: &Context<'gc>) -> Value<'gc> {
        self.to_string().into_value(cx)
    }
}

impl<'gc> IntoValue<'gc> for String {
    fn into_value(self, cx: &Context<'gc>) -> Value<'gc> {
        Value(ValueInner::String(StringValue::new_ptr(cx, self)))
    }
}
