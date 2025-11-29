use crate::{
    context::Context,
    error::ErrorPtr,
    function::{Function, FunctionPtr, NO_OPERAND, opcode},
};

pub fn compile<'gc>(cx: &Context<'gc>, source: &str) -> Result<FunctionPtr<'gc>, ErrorPtr<'gc>> {
    let mut builder = Function::builder();
    builder.arity(0);

    builder.instruction(opcode::INT, 3);
    builder.instruction(opcode::INT, 4);
    builder.instruction(opcode::ADD, NO_OPERAND);

    builder.instruction(opcode::INT, 2000);
    builder.instruction(opcode::YIELD, NO_OPERAND);

    builder.instruction(opcode::RETURN, NO_OPERAND);

    Ok(builder.build_ptr(cx))
}
