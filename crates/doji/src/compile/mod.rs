use crate::{
    context::Context,
    error::ErrorPtr,
    function::{Function, FunctionPtr, opcode},
};

pub fn compile<'gc>(cx: &Context<'gc>, source: &str) -> Result<FunctionPtr<'gc>, ErrorPtr<'gc>> {
    Ok(Function::builder()
        .arity(0)
        .instruction(opcode::INT, 3)
        .instruction(opcode::INT, 4)
        .instruction(opcode::ADD, 0)
        .instruction(opcode::RETURN, 0)
        .build_ptr(cx))
}
