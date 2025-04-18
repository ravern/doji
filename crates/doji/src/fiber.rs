use gc_arena::{Collect, Gc, Mutation};

use crate::{
    error::Error,
    function::{Constant, Instruction, opcode},
    value::{Closure, Value},
};

#[derive(Collect)]
#[collect(no_drop)]
pub struct Fiber<'gc> {
    current_frame: Frame<'gc>,
    stack: Vec<Value<'gc>>,
    call_stack: Vec<Frame<'gc>>,
}

impl<'gc> Fiber<'gc> {
    pub fn new(closure: Gc<'gc, Closure<'gc>>) -> Self {
        Fiber {
            current_frame: Frame::with_closure(closure),
            stack: Vec::new(),
            call_stack: Vec::new(),
        }
    }

    pub fn step(&mut self, mc: &Mutation<'gc>) -> Result<Step<'gc>, Error> {
        loop {
            let instruction = *self
                .current_frame
                .code()
                .get(self.current_frame.ip)
                .expect("invalid ip");

            self.current_frame.ip += 1;

            match instruction.opcode() {
                opcode::NO_OP => {}

                opcode::INT => {
                    self.stack.push(Value::Int(instruction.operand() as i64));
                }

                opcode::ADD => {
                    let b = self.stack.pop().unwrap();
                    let a = self.stack.pop().unwrap();
                    match (a, b) {
                        (Value::Int(a), Value::Int(b)) => self.stack.push(Value::Int(a + b)),
                        _ => unimplemented!(),
                    }
                }

                opcode::RETURN => {
                    return Ok(Step::Done(self.stack.pop().unwrap()));
                }

                _ => unimplemented!(),
            }
        }
    }
}

pub enum Step<'gc> {
    Yield(Value<'gc>),
    Done(Value<'gc>),
}

#[derive(Collect)]
#[collect(no_drop)]
struct Frame<'gc> {
    callable: Callable<'gc>,
    ip: usize,
    bp: usize,
}

impl<'gc> Frame<'gc> {
    fn with_closure(closure: Gc<'gc, Closure<'gc>>) -> Self {
        Frame {
            callable: Callable::Closure(closure),
            ip: 0,
            bp: 0,
        }
    }

    fn constant(&self, constant: usize) -> Option<Constant<'gc>> {
        match &self.callable {
            Callable::Closure(closure) => closure.function().constants.get(constant).cloned(),
        }
    }

    fn code(&self) -> &[Instruction] {
        match &self.callable {
            Callable::Closure(closure) => &closure.function().code,
        }
    }
}

#[derive(Collect)]
#[collect(no_drop)]
enum Callable<'gc> {
    Closure(Gc<'gc, Closure<'gc>>),
}
