pub use self::error::CompileError;
use crate::{context::Context, function::FunctionPtr};

mod error;

pub fn compile<'gc>(cx: &Context<'gc>, source: &str) -> Result<FunctionPtr<'gc>, CompileError> {
    todo!()
}
