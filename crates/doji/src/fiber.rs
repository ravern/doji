use std::env;

use crate::{
    code::{CodeOffset, ConstantIndex, Instruction},
    env::Environment,
    error::Error,
    value::{Function, Value},
};

pub struct Fiber<'gc> {
    function: Function,
    code_offset: CodeOffset,
    stack: Stack<'gc>,
    call_stack: CallStack,
}

impl<'gc> Fiber<'gc> {
    pub fn new(function: Function) -> Fiber<'gc> {
        Fiber {
            function,
            code_offset: CodeOffset::from(0),
            stack: Stack::new(),
            call_stack: CallStack::new(),
        }
    }

    pub fn with_stack(function: Function, stack: Stack<'gc>) -> Fiber<'gc> {
        Fiber {
            function,
            code_offset: CodeOffset::from(0),
            stack,
            call_stack: CallStack::new(),
        }
    }

    pub async fn resume(&mut self, env: &Environment<'gc>) -> Result<Value<'gc>, Error> {
        let code_offset = self.code_offset.as_usize();
        while code_offset < self.function.size() {
            self.step(env).await?;
        }
        Ok(self.stack.get(0).unwrap().clone())
    }

    pub async fn step(&mut self, env: &Environment<'gc>) -> Result<(), Error> {
        match self.instruction()? {
            Instruction::Constant(index) => {
                let constant = self.constant(env, index)?;
                self.stack.push(constant)
            }
            Instruction::Add => {
                let right = self.stack.pop().unwrap();
                let left = self.stack.pop().unwrap();
                match (left, right) {
                    (Value::Int(left), Value::Int(right)) => {
                        self.stack.push(Value::Int(left + right))
                    }
                    _ => panic!("Expected two integers"),
                }
            }
            _ => panic!("Unknown instruction"),
        }

        Ok(())
    }

    fn instruction(&self) -> Result<Instruction, Error> {
        self.function
            .instruction(self.code_offset)
            .ok_or_else(|| Error::CodeOffsetOutOfBounds {
                code_offset: self.code_offset,
            })
    }

    fn constant(&self, env: &Environment<'gc>, index: ConstantIndex) -> Result<Value<'gc>, Error> {
        env.constant(index)
            .ok_or_else(|| Error::InvalidConstantIndex {
                code_offset: self.code_offset,
                index,
            })
    }
}

struct CallStack {
    frames: Vec<CallStackFrame>,
}

struct CallStackFrame {
    stack_base: usize,
    code_offset: usize,
}

impl CallStack {
    fn new() -> CallStack {
        CallStack { frames: Vec::new() }
    }

    fn push(&mut self, stack_base: usize, code_offset: usize) {
        self.frames.push(CallStackFrame {
            stack_base,
            code_offset,
        });
    }

    fn pop(&mut self) -> Option<CallStackFrame> {
        self.frames.pop()
    }
}

pub struct Stack<'gc> {
    base: usize,
    values: Vec<Value<'gc>>,
}

impl<'gc> Stack<'gc> {
    fn new() -> Stack<'gc> {
        Stack {
            base: 0,
            values: Vec::new(),
        }
    }

    fn get(&self, index: usize) -> Option<&Value<'gc>> {
        self.values.get(self.base + index)
    }

    fn push(&mut self, value: Value<'gc>) {
        self.values.push(value);
    }

    fn pop(&mut self) -> Option<Value<'gc>> {
        self.values.pop()
    }
}
