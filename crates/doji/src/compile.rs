use std::rc::Rc;

use crate::{
    code::{Chunk, ChunkBuilder, ConstantIndex, Instruction},
    env::Environment,
    error::Error,
    value::Value,
};

pub struct Compiler {}

impl Compiler {
    fn compile<'gc>(
        &mut self,
        env: &mut Environment<'gc>,
        source: &str,
    ) -> Result<Rc<Chunk>, Error> {
        let index_two = env.add_constant(Value::Int(2));
        let index_four = env.add_constant(Value::Int(4));
        Ok(Rc::new(
            ChunkBuilder::new(0)
                .code([
                    Instruction::Constant(ConstantIndex::from(index_two)),
                    Instruction::Constant(ConstantIndex::from(index_four)),
                    Instruction::Add,
                ])
                .build(),
        ))
    }
}
