use std::rc::Rc;

use crate::{
    bytecode::{Instruction, Module, Program},
    error::RuntimeError,
    gc::Heap,
    value::{Object, Value},
};

pub struct Fiber<'gc> {
    program: Rc<Program>,
    module_path: Box<str>,
    program_counter: usize,
    stack: FiberStack<'gc>,
}

impl<'gc> Fiber<'gc> {
    pub fn new(program: Rc<Program>, module_path: &str, program_counter: usize) -> Self {
        Self {
            program,
            module_path: module_path.into(),
            program_counter,
            stack: FiberStack::new(),
        }
    }

    pub async fn run(&mut self, heap: &mut Heap<'gc>) {}

    async fn step(&mut self, heap: &mut Heap<'gc>) -> Result<(), RuntimeError> {
        let instruction = self.get_instruction()?;
        match instruction {
            Instruction::Noop => {}
            Instruction::Nil { dest } => {
                self.stack.set(dest, Value::Nil);
            }
            Instruction::True { dest } => {
                self.stack.set(dest, Value::Bool(true));
            }
            Instruction::False { dest } => {
                self.stack.set(dest, Value::Bool(false));
            }
            Instruction::Int { dest, value } => {
                self.stack.set(dest, Value::Int(value as i64));
            }
            Instruction::Const { dest, index } => {
                let constant = self.get_constant(index)?;
                match constant {
                    crate::bytecode::Constant::Int(value) => {
                        self.stack.set(dest, Value::Int(*value));
                    }
                    crate::bytecode::Constant::Float(value) => {
                        self.stack.set(dest, Value::Float(*value));
                    }
                    crate::bytecode::Constant::String(value) => {
                        let string = heap.allocate(Object::String(value.clone()));
                        self.stack.set(dest, Value::Object(string.as_handle()));
                    }
                }
            }
            Instruction::Add { dest, left, right } => {
                let left = self
                    .stack
                    .get(left)
                    .ok_or(RuntimeError::InvalidStackIndex {
                        module_path: self.module_path.clone(),
                        stack_index: left,
                    })?;
                let right = self
                    .stack
                    .get(right)
                    .ok_or(RuntimeError::InvalidStackIndex {
                        module_path: self.module_path.clone(),
                        stack_index: right,
                    })?;
                match (left, right) {
                    (Value::Int(left), Value::Int(right)) => {
                        self.stack.set(dest, Value::Int(left + right));
                    }
                    (Value::Float(left), Value::Int(right)) => {
                        self.stack.set(dest, Value::Float(left + right as f64));
                    }
                    (Value::Int(left), Value::Float(right)) => {
                        self.stack.set(dest, Value::Float(left as f64 + right));
                    }
                    (Value::Float(left), Value::Float(right)) => {
                        self.stack.set(dest, Value::Float(left + right));
                    }
                    _ => {
                        return Err(RuntimeError::InvalidArgumentType {
                            module_path: self.module_path.clone(),
                        })
                    }
                }
            }
            _ => todo!(),
        }

        Ok(())
    }

    fn get_module(&self) -> Result<&Module, RuntimeError> {
        self.program
            .modules
            .get(&self.module_path)
            .ok_or(RuntimeError::InvalidModulePath {
                module_path: self.module_path.clone(),
            })
    }

    fn get_instruction(&self) -> Result<Instruction, RuntimeError> {
        self.get_module()?
            .code
            .get(self.program_counter)
            .copied()
            .ok_or(RuntimeError::InvalidProgramCounter {
                module_path: self.module_path.clone(),
                program_counter: self.program_counter,
            })
    }

    fn get_constant(&self, index: u32) -> Result<&crate::bytecode::Constant, RuntimeError> {
        self.get_module()?
            .constants
            .get(index as usize)
            .ok_or(RuntimeError::InvalidConstantIndex {
                module_path: self.module_path.clone(),
                constant_index: index,
            })
    }
}

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

    pub fn get(&self, index: u16) -> Option<Value<'gc>> {
        let absolute_index = self.base + index as usize;
        self.values.get(absolute_index).cloned()
    }

    pub fn set(&mut self, index: u16, value: Value<'gc>) {
        let absolute_index = self.base + index as usize;
        if self.values.len() <= absolute_index {
            self.values.resize(absolute_index + 1, Value::Uninitialized);
        }
        *self.values.get_mut(absolute_index).unwrap() = value;
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
