use crate::{
    context::Context,
    error::ErrorPtr,
    function::{Function, FunctionPtr, opcode},
};

pub fn compile<'gc>(cx: &Context<'gc>, source: &str) -> Result<FunctionPtr<'gc>, ErrorPtr<'gc>> {
    let mut builder = Function::builder();
    builder.arity(0);
    builder.instruction(opcode::INT, 3);
    builder.instruction(opcode::INT, 4);
    builder.instruction(opcode::ADD, 0);
    builder.instruction(opcode::RETURN, 0);
    Ok(builder.build_ptr(cx))
}
