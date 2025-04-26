use self::error::CompileError;
use crate::function::FunctionPtr;

mod error;

pub fn compile<'gc>(source: &str) -> Result<FunctionPtr<'gc>, CompileError> {
    todo!()
}
