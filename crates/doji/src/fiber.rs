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

                opcode::ADD => self.do_int_or_float_op(|a, b| a + b, |a, b| a + b)?,
                opcode::SUB => self.do_int_or_float_op(|a, b| a - b, |a, b| a - b)?,
                opcode::MUL => self.do_int_or_float_op(|a, b| a * b, |a, b| a * b)?,
                opcode::DIV => self.do_int_or_float_op(|a, b| a / b, |a, b| a / b)?,
                opcode::MOD => self.do_int_op(|a, b| a % b)?,

                opcode::RETURN => {
                    return Ok(Step::Done(self.stack.pop().unwrap()));
                }

                _ => unimplemented!(),
            }
        }
    }

    fn do_int_op<F, T>(&mut self, f: F) -> Result<(), Error>
    where
        F: Fn(i64, i64) -> T,
        T: Into<Value<'gc>>,
    {
        let b: i64 = self.pop().try_into()?;
        let a: i64 = self.pop().try_into()?;
        self.stack.push(f(a, b).into());
        Ok(())
    }

    fn do_int_or_float_op<F, G, T, U>(&mut self, f: F, g: G) -> Result<(), Error>
    where
        F: Fn(i64, i64) -> T,
        G: Fn(f64, f64) -> U,
        T: Into<Value<'gc>>,
        U: Into<Value<'gc>>,
    {
        enum Number {
            Int(i64),
            Float(f64),
        }

        impl<'gc> TryFrom<Value<'gc>> for Number {
            type Error = Error;

            fn try_from(value: Value<'gc>) -> Result<Self, Self::Error> {
                let i_result = value.clone().try_into().map(Number::Int);
                let f_result = value.try_into().map(Number::Float);
                i_result.or(f_result)
            }
        }

        use Number::*;

        let b: Number = self.pop().try_into()?;
        let a: Number = self.pop().try_into()?;
        self.stack.push(match (a, b) {
            (Int(a), Int(b)) => f(a, b).into(),
            (Float(a), Float(b)) => g(a, b).into(),
            (Int(a), Float(b)) => g(a as f64, b).into(),
            (Float(a), Int(b)) => g(a, b as f64).into(),
        });
        Ok(())
    }

    fn pop(&mut self) -> Value<'gc> {
        self.stack.pop().expect("stack underflow")
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
