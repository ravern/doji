use std::fmt::{self, Display, Formatter};

use gc_arena::{Collect, DynamicRoot, Rootable};

use crate::{context::Context, error::WrongTypeError, string::StringPtr};

pub type RootValue = DynamicRoot<Rootable![Value<'_>]>;

#[derive(Debug)]
pub enum ValueType {
    Nil,
    Bool,
    Int,
    Float,
    String,
}

impl Display for ValueType {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::Nil => write!(f, "nil"),
            Self::Bool => write!(f, "bool"),
            Self::Int => write!(f, "int"),
            Self::Float => write!(f, "float"),
            Self::String => write!(f, "string"),
        }
    }
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Value<'gc>(ValueInner<'gc>);

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
enum ValueInner<'gc> {
    Nil,
    Bool(bool),
    Int(i64),
    Float(f64),
    String(StringPtr<'gc>),
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
        }
    }
}

impl<'gc> Default for Value<'gc> {
    fn default() -> Self {
        Self::NIL
    }
}

pub trait TryFromValue<'gc>: Sized {
    fn try_from_value(value: Value<'gc>, cx: &Context<'gc>) -> Result<Self, WrongTypeError>;
}

macro_rules! impl_try_from {
    ($ty:ty, $variant:ident, $expected:expr) => {
        impl<'gc> TryFromValue<'gc> for $ty {
            fn try_from_value(
                value: Value<'gc>,
                _cx: &Context<'gc>,
            ) -> Result<Self, WrongTypeError> {
                match value.0 {
                    ValueInner::$variant(v) => Ok(v),
                    _ => Err(WrongTypeError {
                        expected: $expected,
                        actual: value.ty(),
                    }),
                }
            }
        }
    };
}

impl_try_from!(bool, Bool, ValueType::Bool);
impl_try_from!(i64, Int, ValueType::Int);
impl_try_from!(f64, Float, ValueType::Float);

impl<'gc> TryFromValue<'gc> for RootValue {
    fn try_from_value(value: Value<'gc>, cx: &Context<'gc>) -> Result<Self, WrongTypeError> {
        Ok(cx.root(value))
    }
}

pub trait ValueTryInto<'gc, T>: Sized {
    fn value_try_into(self, cx: &Context<'gc>) -> Result<T, WrongTypeError>
    where
        T: TryFromValue<'gc>;
}

impl<'gc, T> ValueTryInto<'gc, T> for Value<'gc>
where
    T: TryFromValue<'gc>,
{
    fn value_try_into(self, cx: &Context<'gc>) -> Result<T, WrongTypeError> {
        T::try_from_value(self, cx)
    }
}

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
