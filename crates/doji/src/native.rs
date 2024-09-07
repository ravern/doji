use crate::value::Value;

pub trait NativeModule {
    fn build<'gc>() -> Value<'gc>;
}
