use crate::{
    code::{ChunkBuilder, ConstantIndex, Instruction, StackSlot},
    env::Environment,
    error::Error,
    value::{Function, Value},
};

pub struct Compiler {}

impl Compiler {
    pub fn compile<'gc>(
        &mut self,
        env: &Environment<'gc>,
        source: &str,
    ) -> Result<Function, Error> {
        let index_two = env.add_constant(Value::Int(2));
        let index_four = env.add_constant(Value::Int(4));
        Ok(Function::new(
            ChunkBuilder::new(0)
                .code([
                    Instruction::Constant(ConstantIndex::from(index_two)),
                    Instruction::Constant(ConstantIndex::from(index_four)),
                    Instruction::Add,
                    Instruction::Store(StackSlot::from(0)),
                    Instruction::Return,
                ])
                .build(),
        ))
    }
}
