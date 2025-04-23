use gc_arena::{Collect, Gc, Mutation, lock::GcRefLock};

use crate::{
    error::Error,
    function::{Constant, Instruction, opcode},
    io,
    native::{self, Native, StepFn},
    value::{Closure, Value},
};

#[derive(Collect)]
#[collect(no_drop)]
pub(crate) struct Fiber<'gc> {
    current_frame: Frame<'gc>,
    stack: Vec<Value<'gc>>,
    call_stack: Vec<Frame<'gc>>,
}

impl<'gc> Fiber<'gc> {
    pub fn new(closure: GcRefLock<'gc, Closure<'gc>>) -> Self {
        Fiber {
            current_frame: Frame::Closure(ClosureFrame::new(closure, 0)),
            stack: Vec::new(),
            call_stack: Vec::new(),
        }
    }

    pub fn step(&mut self, mc: &Mutation<'gc>) -> Result<Step<'gc>, Error> {
        loop {
            match &mut self.current_frame {
                Frame::Closure(frame) => {
                    let instruction = frame.current_instruction();
                    frame.ip += 1;

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

                        opcode::CALL => self.call(mc, instruction.operand())?,
                        opcode::RETURN => match self.call_stack.pop() {
                            Some(frame) => self.current_frame = frame,
                            None => {
                                return Ok(Step::Return(self.pop()));
                            }
                        },

                        _ => unimplemented!(),
                    }
                }

                Frame::Native(frame) => {
                    let step = frame.current_step()(mc);
                    frame.sp += 1;

                    match step {
                        native::Step::Yield(operation) => {
                            return Ok(Step::Yield(operation));
                        }
                        native::Step::Call(arity) => self.call(mc, arity)?,
                        native::Step::Return(value) => {
                            return Ok(Step::Return(value));
                        }
                    }
                }
            }
        }
    }

    fn do_int_op<F, T>(&mut self, int_op: F) -> Result<(), Error>
    where
        F: Fn(i64, i64) -> T,
        T: Into<Value<'gc>>,
    {
        let b: i64 = self.pop().try_into()?;
        let a: i64 = self.pop().try_into()?;
        self.stack.push(int_op(a, b).into());
        Ok(())
    }

    fn do_int_or_float_op<F, G, T, U>(&mut self, int_op: F, float_op: G) -> Result<(), Error>
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
            (Int(a), Int(b)) => int_op(a, b).into(),
            (Float(a), Float(b)) => float_op(a, b).into(),
            (Int(a), Float(b)) => float_op(a as f64, b).into(),
            (Float(a), Int(b)) => float_op(a, b as f64).into(),
        });
        Ok(())
    }

    fn call(&mut self, mc: &Mutation<'gc>, arity: usize) -> Result<(), Error> {
        unimplemented!()
    }

    fn push(&mut self, value: Value<'gc>) {
        self.stack.push(value);
    }

    fn pop(&mut self) -> Value<'gc> {
        self.stack.pop().expect("stack underflow")
    }

    fn peek(&self, index_from_top: usize) -> Value<'gc> {
        self.load_absolute(self.stack.len() - index_from_top - 1)
    }

    fn load(&self, index: usize) -> Value<'gc> {
        self.load_absolute(self.current_frame.bp() + index)
    }

    fn load_absolute(&self, index: usize) -> Value<'gc> {
        *self.stack.get(index).expect("invalid stack access")
    }

    fn store(&mut self, index: usize, value: Value<'gc>) {
        self.store_absolute(self.current_frame.bp() + index, value);
    }

    fn store_absolute(&mut self, index: usize, value: Value<'gc>) {
        *self.stack.get_mut(index).expect("invalid stack access") = value;
    }
}

pub(crate) enum Step<'gc> {
    Yield(io::Operation),
    Return(Value<'gc>),
}

#[derive(Collect)]
#[collect(no_drop)]
enum Frame<'gc> {
    Closure(ClosureFrame<'gc>),
    Native(NativeFrame),
}

impl<'gc> Frame<'gc> {
    fn bp(&self) -> usize {
        match self {
            Frame::Closure(frame) => frame.bp,
            Frame::Native(frame) => frame.bp,
        }
    }
}

#[derive(Collect)]
#[collect(no_drop)]
struct NativeFrame {
    native: Native,
    sp: usize,
    bp: usize,
}

impl NativeFrame {
    fn new(native: Native, bp: usize) -> Self {
        Self { native, sp: 0, bp }
    }

    fn current_step(&self) -> StepFn {
        self.native.steps.get(self.sp).expect("invalid sp").clone()
    }
}

#[derive(Collect)]
#[collect(no_drop)]
struct ClosureFrame<'gc> {
    closure: GcRefLock<'gc, Closure<'gc>>,
    ip: usize,
    bp: usize,
}

impl<'gc> ClosureFrame<'gc> {
    fn new(closure: GcRefLock<'gc, Closure<'gc>>, bp: usize) -> Self {
        Self { closure, ip: 0, bp }
    }

    fn constant(&self, constant: usize) -> Option<Constant<'gc>> {
        self.closure
            .borrow()
            .function()
            .constants
            .get(constant)
            .cloned()
    }

    fn current_instruction(&self) -> Instruction {
        *self
            .closure
            .borrow()
            .function()
            .code
            .get(self.ip)
            .expect("invalid ip")
    }
}
