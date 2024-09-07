use std::rc::Rc;

use crate::{
    code::{Function, Instruction},
    error::Error,
    value::Value,
};

pub struct Fiber<'gc> {
    function: Rc<Function>,
    offset: usize,
    stack: Stack<'gc>,
}

impl<'gc> Fiber<'gc> {
    pub fn new(function: Rc<Function>) -> Fiber<'gc> {
        Fiber {
            function,
            offset: 0,
            stack: Stack::new(),
        }
    }

    pub async fn resume(&mut self) -> Result<Value<'gc>, Error> {
        while self.offset < self.function.size() {
            self.step().await?;
        }
        Ok(self.stack.get(0).unwrap().clone())
    }

    pub async fn step(&mut self) -> Result<(), Error> {
        let instruction = self.function.instruction(self.offset).unwrap();
        self.offset += 1;

        match instruction {
            Instruction::Int(int) => self.stack.push(Value::Int(int as i64)),
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
}

struct Stack<'gc> {
    base: usize,
    items: Vec<Value<'gc>>,
}

impl<'gc> Stack<'gc> {
    fn new() -> Stack<'gc> {
        Stack {
            base: 0,
            items: Vec::new(),
        }
    }

    fn get(&self, index: usize) -> Option<&Value<'gc>> {
        self.items.get(self.base + index)
    }

    fn push(&mut self, value: Value<'gc>) {
        self.items.push(value);
    }

    fn pop(&mut self) -> Option<Value<'gc>> {
        self.items.pop()
    }
}
