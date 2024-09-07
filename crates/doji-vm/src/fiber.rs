use std::ops::{Add, Div, Mul, Rem, Sub};

use doji_program::{opcode::*, Chunk, Constant, Program, MAX_OPERAND_WIDTH};

use crate::{
    error::{RuntimeError, RuntimeErrorContext},
    gc::Heap,
    value::{Value, ValueType},
};

pub struct Fiber<'gc> {
    chunk_index: usize,
    acc_operand: u64,
    num_operand_exts: usize,
    bytecode_offset: usize,
    stack: FiberStack<'gc>,
}

impl<'gc> Fiber<'gc> {
    pub fn new(chunk_index: usize) -> Self {
        Self {
            chunk_index,
            acc_operand: 0,
            num_operand_exts: 0,
            bytecode_offset: 0,
            stack: FiberStack::new(),
        }
    }

    pub async fn resume(
        &mut self,
        program: &Program,
        heap: &Heap<'gc>,
    ) -> Result<(), RuntimeError> {
        let chunk = self.chunk(program);
        while self.bytecode_offset < chunk.size() {
            self.step(program, heap).await?;
        }
        Ok(())
    }

    async fn step(&mut self, program: &Program, heap: &Heap<'gc>) -> Result<(), RuntimeError> {
        macro_rules! arithmetic {
            ($op:ident) => {{
                let right = self.stack_pop(program)?;
                let left = self.stack_pop(program)?;
                match (left, right) {
                    (Value::Int(left), Value::Int(right)) => {
                        self.stack.push(Value::Int(left.$op(right)));
                    }
                    (Value::Int(left), Value::Float(right)) => {
                        self.stack.push(Value::Float((left as f64).$op(right)));
                    }
                    (Value::Float(left), Value::Int(right)) => {
                        self.stack.push(Value::Float(left.$op(right as f64)));
                    }
                    (Value::Float(left), Value::Float(right)) => {
                        self.stack.push(Value::Float(left.$op(right)));
                    }
                    (Value::Int(_), received) | (Value::Float(_), received) | (received, _) => {
                        return Err(RuntimeError::invalid_type(
                            self.error_context(program),
                            [ValueType::Int, ValueType::Float],
                            received.ty(),
                        ));
                    }
                }
            }};
        }

        let opcode = self.opcode(program)?;
        let operand = self.operand(program)?;

        if opcode == OP_EXT {
            self.num_operand_exts += 1;
        } else {
            self.acc_operand = 0;
            self.num_operand_exts = 0;
        }

        match opcode {
            OP_NOP => {}

            OP_EXT => {}

            OP_NIL => self.stack.push(Value::Nil),
            OP_TRUE => self.stack.push(Value::Bool(true)),
            OP_FALSE => self.stack.push(Value::Bool(false)),
            OP_INT => {
                let int = transmute_usize_to_i64(operand);
                self.stack.push(Value::Int(int));
            }
            OP_CONST => {
                let constant = self.constant(program, operand)?;
                self.stack.push(Value::from_constant(constant, heap));
            }

            OP_ADD => arithmetic!(add),
            OP_SUB => arithmetic!(sub),
            OP_MUL => arithmetic!(mul),
            OP_DIV => arithmetic!(div),
            OP_REM => arithmetic!(rem),

            _ => unreachable!(),
        }

        self.bytecode_offset = self.next_bytecode_offset();

        Ok(())
    }

    fn chunk<'p>(&self, program: &'p Program) -> &'p Chunk {
        program
            .chunk(self.chunk_index)
            .expect("fiber contains invalid chunk index")
    }

    fn constant<'p>(&self, program: &'p Program, index: usize) -> Result<Constant, RuntimeError> {
        program
            .constant(index)
            .cloned()
            .ok_or_else(|| RuntimeError::invalid_constant_index(self.error_context(program), index))
    }

    fn stack_get<'p>(&self, program: &'p Program, slot: usize) -> Result<Value<'gc>, RuntimeError> {
        self.stack
            .get(slot)
            .ok_or_else(|| RuntimeError::invalid_stack_slot(self.error_context(program), slot))
    }

    fn stack_pop<'p>(&mut self, program: &'p Program) -> Result<Value<'gc>, RuntimeError> {
        self.stack
            .pop()
            .ok_or_else(|| RuntimeError::stack_underflow(self.error_context(program)))
    }

    fn opcode<'p>(&self, program: &'p Program) -> Result<u8, RuntimeError> {
        self.next_bytecode_offset(); // check for overflow
        self.chunk(program)
            .byte(self.bytecode_offset)
            .ok_or_else(|| RuntimeError::invalid_bytecode_offset(self.error_context(program)))
    }

    fn operand<'p>(&mut self, program: &'p Program) -> Result<usize, RuntimeError> {
        self.next_bytecode_offset(); // check for overflow
        let operand = self
            .chunk(program)
            .byte(self.bytecode_offset + 1)
            .ok_or_else(|| RuntimeError::invalid_bytecode_offset(self.error_context(program)))?;
        self.extend_operand(program, operand)
    }

    fn extend_operand<'p>(
        &mut self,
        program: &'p Program,
        operand: u8,
    ) -> Result<usize, RuntimeError> {
        if self.num_operand_exts >= OPERAND_WIDTH {
            return Err(RuntimeError::operand_width_exceeded(
                self.error_context(program),
            ));
        }
        self.acc_operand = (self.acc_operand << 8) | operand as usize;
        Ok(self.acc_operand)
    }

    fn next_bytecode_offset(&self) -> usize {
        self.bytecode_offset
            .checked_add(2)
            .expect("chunk size exceeds maximum integer width")
    }

    fn error_context<'p>(&self, program: &'p Program) -> RuntimeErrorContext {
        let chunk = self.chunk(program);
        RuntimeErrorContext {
            module_path: chunk.module_path.clone(),
            chunk_name: chunk.name.clone(),
            bytecode_offset: self.bytecode_offset,
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

    pub fn get(&self, slot: usize) -> Option<Value<'gc>> {
        let index = self.base + slot;
        self.values.get(index).cloned()
    }

    pub fn push(&mut self, value: Value<'gc>) {
        self.values.push(value);
    }

    pub fn pop(&mut self) -> Option<Value<'gc>> {
        self.values.pop()
    }
}

fn transmute_usize_to_i64(value: usize) -> i64 {
    let bytes = (value as u64).to_ne_bytes();
    i64::from_ne_bytes(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run<'gc>(heap: &Heap<'gc>, program: &Program) -> Value<'gc> {
        smol::block_on(async {
            let mut fiber = Fiber::new(0);
            fiber.resume(&program, &heap).await.unwrap();
            fiber.stack.get(0)
        })
        .expect("fiber stack empty after running")
    }

    #[test]
    fn int() {
        let heap = Heap::new();
        let program = Program {
            constants: [].into(),
            chunks: [Chunk {
                module_path: "src/main.doji".into(),
                name: "main".into(),
                bytecode: [OP_INT, 0x23u8].into(),
            }]
            .into(),
        };
        assert_eq!(run(&heap, &program), Value::Int(0x23));
    }

    #[test]
    fn ext() {
        let heap = Heap::new();
        let program = Program {
            constants: [].into(),
            chunks: [Chunk {
                module_path: "src/main.doji".into(),
                name: "main".into(),
                bytecode: [OP_EXT, 0x12u8, OP_INT, 0x34u8].into(),
            }]
            .into(),
        };
        assert_eq!(run(&heap, &program), Value::Int(0x1234));
    }

    #[test]
    fn add() {
        let heap = Heap::new();
        let program = Program {
            constants: [].into(),
            chunks: [Chunk {
                module_path: "src/main.doji".into(),
                name: "main".into(),
                bytecode: [
                    OP_INT, 0x12u8, OP_INT, 0x34u8, OP_ADD, 0x00u8, OP_INT, 0x56u8, OP_ADD, 0x00u8,
                ]
                .into(),
            }]
            .into(),
        };
        assert_eq!(run(&heap, &program), Value::Int(0x9c));
    }
}

// use smol::LocalExecutor;

// impl<'bc> Fiber<'bc> {
//     pub fn testing_123() {
// let ex = LocalExecutor::new();

// let code = [0, 1, 2, 3];

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
