use crate::{
    code::{Chunk, ChunkBuilder, CodeOffset, Instruction, StackSlot, Upvalue, UpvalueIndex},
    env::Environment,
    error::{Error, ErrorContext, ErrorKind},
    value::{Function, NativeFunctionHandle, TypeError, Value, ValueType},
};

pub struct Compiler {}

impl Compiler {
    pub fn compile<'gc>(
        &mut self,
        env: &Environment<'gc>,
        source: &str,
    ) -> Result<Function, Error> {
        // let index_two = env.add_constant(Value::Int(2));
        // let index_four = env.add_constant(Value::Int(4));
        // let index_add = env.add_constant(Value::NativeFunction(NativeFunctionHandle::new(
        //     2,
        //     |env, heap, stack| {
        //         let right = stack.pop().unwrap();
        //         let left = stack.pop().unwrap();
        //         match (&left, &right) {
        //             (Value::Int(left), Value::Int(right)) => {
        //                 stack.set(StackSlot::from(0), Value::Int(left + right));
        //                 Ok(())
        //             }
        //             _ => Err(Error::new(
        //                 ErrorContext {
        //                     code_offset: CodeOffset::from(0),
        //                 },
        //                 ErrorKind::WrongType(TypeError {
        //                     expected: [ValueType::Int].into(),
        //                     found: left.ty(),
        //                 }),
        //             )),
        //         }
        //     },
        // )));
        // Ok(Function::new(
        //     0,
        //     ChunkBuilder::new()
        //         .code([
        //             Instruction::Constant(index_add),
        //             Instruction::Constant(index_two),
        //             Instruction::Constant(index_four),
        //             Instruction::Call(2),
        //             Instruction::Store(StackSlot::from(0)),
        //             Instruction::Return,
        //         ])
        //         .build(),
        // ))

        Ok(Function::new(
            0,
            ChunkBuilder::new()
                .code([
                    Instruction::Closure(
                        env.add_function(Function::new(
                            2,
                            ChunkBuilder::new()
                                .code([
                                    Instruction::Closure(
                                        env.add_function(Function::new(
                                            0,
                                            ChunkBuilder::new()
                                                .code([
                                                    Instruction::UpvalueLoad(UpvalueIndex::from(0)),
                                                    Instruction::UpvalueLoad(UpvalueIndex::from(1)),
                                                    Instruction::Add,
                                                    Instruction::Store(StackSlot::from(0)),
                                                    Instruction::Return,
                                                ])
                                                .upvalue(Upvalue::Local(StackSlot::from(1)))
                                                .upvalue(Upvalue::Local(StackSlot::from(2)))
                                                .build(),
                                        )),
                                    ),
                                    Instruction::Store(StackSlot::from(0)),
                                    Instruction::UpvalueClose,
                                    Instruction::UpvalueClose,
                                    Instruction::Return,
                                ])
                                .build(),
                        )),
                    ),
                    Instruction::Constant(env.add_constant(Value::Int(34))),
                    Instruction::Constant(env.add_constant(Value::Int(45))),
                    Instruction::Call(2),
                    Instruction::Call(0),
                    Instruction::Store(StackSlot::from(0)),
                    Instruction::Return,
                ])
                .build(),
        ))
    }
}
