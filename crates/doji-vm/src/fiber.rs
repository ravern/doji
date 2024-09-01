use doji_bytecode::{
    operand::{CodeOffset, StackSlot},
    Chunk, ChunkIndex, Constant, Instruction, Program,
};

use crate::{
    error::{RuntimeError, RuntimeErrorContext},
    gc::Heap,
    value::Value,
};

pub struct Fiber<'gc> {
    chunk_index: ChunkIndex,
    code_offset: CodeOffset,
    stack: FiberStack<'gc>,
}

impl<'gc> Fiber<'gc> {
    pub fn new(chunk_index: ChunkIndex) -> Self {
        Self {
            chunk_index,
            code_offset: CodeOffset::zero(),
            stack: FiberStack::new(),
        }
    }

    pub async fn run(&mut self, program: &Program, heap: &Heap<'gc>) -> Result<(), RuntimeError> {
        let chunk = self.chunk(program);

        while self.code_offset.as_usize() < chunk.len() {
            self.step(program, heap).await?;
        }

        Ok(())
    }

    async fn step(&mut self, program: &Program, heap: &Heap<'gc>) -> Result<(), RuntimeError> {
        let chunk = self.chunk(program);

        let instruction = chunk
            .instruction(self.code_offset)
            .ok_or_else(|| RuntimeError::invalid_code_offset(self.error_context(chunk)))?;

        self.code_offset = self.code_offset.increment();

        match instruction {
            Instruction::Noop => {}
            Instruction::Nil { to } => {
                self.stack.set(to, Value::Nil);
            }
            Instruction::True { to } => {
                self.stack.set(to, Value::Bool(true));
            }
            Instruction::False { to } => {
                self.stack.set(to, Value::Bool(false));
            }
            Instruction::Int { to, from } => {
                self.stack.set(to, Value::Int(from.as_i64()));
            }
            Instruction::Constant { to, from } => {
                let constant = program.constant(from).cloned().ok_or_else(|| {
                    RuntimeError::invalid_constant_index(self.error_context(chunk), from)
                })?;
                match constant {
                    Constant::Int(value) => {
                        self.stack.set(to, Value::Int(value));
                    }
                    Constant::Float(value) => {
                        self.stack.set(to, Value::Float(value));
                    }
                }
            }
            Instruction::Add { to, left, right } => {
                let left = self.stack_get(chunk, left)?;
                let right = self.stack_get(chunk, right)?;
                match (&left, &right) {
                    (Value::Int(left), Value::Int(right)) => {
                        self.stack.set(to, Value::Int(left + right));
                    }
                    (Value::Float(left), Value::Int(right)) => {
                        self.stack.set(to, Value::Float(left + *right as f64));
                    }
                    (Value::Int(left), Value::Float(right)) => {
                        self.stack.set(to, Value::Float(*left as f64 + right));
                    }
                    (Value::Float(left), Value::Float(right)) => {
                        self.stack.set(to, Value::Float(left + right));
                    }
                    _ => {
                        return Err(RuntimeError::invalid_type(
                            self.error_context(chunk),
                            left.ty(),
                            right.ty(),
                        ))
                    }
                }
            }
            _ => todo!(),
        }

        Ok(())
    }

    fn stack_get(&self, chunk: &Chunk, slot: StackSlot) -> Result<Value<'gc>, RuntimeError> {
        self.stack
            .get(slot)
            .and_then(|value| {
                if let Value::Uninitialized = value {
                    None
                } else {
                    Some(value)
                }
            })
            .ok_or_else(|| RuntimeError::invalid_stack_slot(self.error_context(chunk), slot))
    }

    fn chunk<'a>(&self, program: &'a Program) -> &'a Chunk {
        program
            .chunk(self.chunk_index)
            .expect("fiber contains invalid chunk index")
    }

    fn error_context(&self, chunk: &Chunk) -> RuntimeErrorContext {
        RuntimeErrorContext {
            module_path: chunk.module_path.clone(),
            code_offset: self.code_offset,
        }
    }
}

#[derive(Debug)]
pub struct FiberStack<'gc> {
    base: usize,
    values: Vec<Value<'gc>>,
}

impl<'gc> FiberStack<'gc> {
    pub fn new() -> Self {
        Self {
            base: 0,
            values: Vec::new(),
        }
    }

    pub fn get(&self, slot: StackSlot) -> Option<Value<'gc>> {
        let index = self.base + slot.as_usize();
        self.values.get(index).cloned()
    }

    pub fn set(&mut self, slot: StackSlot, value: Value<'gc>) {
        let index = self.base + slot.as_usize();
        if self.values.len() <= index {
            self.values.resize(index + 1, Value::Uninitialized);
        }
        *self.values.get_mut(index).unwrap() = value;
    }
}

#[cfg(test)]
mod tests {
    use doji_bytecode::operand::{IntImmediate, StackSlot};
    use smol::LocalExecutor;

    use super::*;

    #[test]
    fn simple() {
        let ex = LocalExecutor::new();

        let program = Program {
            constants: vec![],
            chunks: vec![Chunk {
                module_path: "src/main.doji".to_string(),
                name: "main".to_string(),
                code: vec![Instruction::Int {
                    to: StackSlot(0),
                    from: IntImmediate(123),
                }],
            }],
        };
        let heap = Heap::new();

        let mut fiber = Fiber::new(ChunkIndex(0));

        smol::block_on(ex.run(async {
            fiber.run(&program, &heap).await.unwrap();
        }));

        assert_eq!(fiber.stack.get(StackSlot(0)), Some(Value::Int(123)));
    }

    #[test]
    fn add() {
        let ex = LocalExecutor::new();

        let program = Program {
            constants: vec![],
            chunks: vec![Chunk {
                module_path: "src/main.doji".to_string(),
                name: "main".to_string(),
                code: vec![
                    Instruction::Int {
                        to: StackSlot(0),
                        from: IntImmediate(123),
                    },
                    Instruction::Int {
                        to: StackSlot(1),
                        from: IntImmediate(123),
                    },
                    Instruction::Add {
                        to: StackSlot(2),
                        left: StackSlot(0),
                        right: StackSlot(1),
                    },
                ],
            }],
        };
        let heap = Heap::new();

        let mut fiber = Fiber::new(ChunkIndex(0));

        smol::block_on(ex.run(async {
            fiber.run(&program, &heap).await.unwrap();
        }));

        assert_eq!(fiber.stack.get(StackSlot(2)), Some(Value::Int(246)));
    }
}

// use smol::LocalExecutor;

// impl<'bc> Fiber<'bc> {
//     pub fn testing_123() {
// let ex = LocalExecutor::new();

// let code = vec![0, 1, 2, 3];

// smol::block_on(ex.run(async move {
//     let task_1 = smol::spawn(async move { Fiber { code: &code, pc: 0 } });
//     let task_2 = smol::spawn(async move { Fiber { code: &code, pc: 0 } });
//     task_1.await;
//     task_2.await;
// }));

// Need scoped (async) tasks for this to be possible
// I think we'll just use Rc instead since it is still quite fast
// LocalExecutor enables non-Send stuff inside async blocks

// A module is some bytecode + constants. It is just a `[usize]` with
// offsets. Chunks contain offset of bytecode. The `usize`s are decoded
// at runtime. This is to make things easier to deal with in Rust (we
// can pass around an `Rc<[usize]>`) and should still be fast. All stored
// in one slice for cache locality.

// Information about what upvalues to capture are stored as a constant.
// Live upvalues (open or closed) are stored in runtime::Closure
//     }
// }
