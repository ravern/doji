use crate::{context::Context, error::ErrorPtr, function::FunctionPtr};

pub fn compile<'gc>(cx: &Context<'gc>, source: &str) -> Result<FunctionPtr<'gc>, ErrorPtr<'gc>> {
    todo!()
}
