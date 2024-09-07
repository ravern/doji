use std::rc::Rc;

use crate::{
    code::{Function, FunctionBuilder, Instruction},
    env::Environment,
    error::Error,
};

fn compile<'gc>(env: &mut Environment<'gc>, source: &str) -> Result<Rc<Function>, Error> {
    Ok(Rc::new(
        FunctionBuilder::new("a".into(), "b".into(), 0)
            .code([Instruction::Int(12), Instruction::Int(34), Instruction::Add])
            .build(),
    ))
}
