use std::thread::current;

use gc_arena::{
    Collect, Gc,
    lock::{GcRefLock, RefLock},
};

use crate::{
    closure::ClosurePtr,
    context::Context,
    error::{EngineError, ErrorPtr},
    function::opcode,
    value::Value,
};

pub type FiberPtr<'gc> = GcRefLock<'gc, FiberValue<'gc>>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct FiberValue<'gc> {
    current_frame: Frame<'gc>,
    stack: Vec<Value<'gc>>,
    call_stack: Vec<Frame<'gc>>,
}

impl<'gc> FiberValue<'gc> {
    pub fn new_ptr(cx: &Context<'gc>, closure: ClosurePtr<'gc>) -> FiberPtr<'gc> {
        Gc::new(
            cx.mutation(),
            RefLock::new(Self {
                current_frame: Frame::new_closure(closure, 0),
                stack: Vec::new(),
                call_stack: Vec::new(),
            }),
        )
    }

    pub fn step(&mut self, cx: &Context<'gc>) -> Step<'gc> {
        match self.current_frame.steppable {
            Steppable::Closure(closure) => self.step_closure(cx, closure),
        }
    }

    pub fn push(&mut self, _cx: &Context<'gc>, value: Value<'gc>) {
        self.stack.push(value);
    }

    fn step_closure(&mut self, cx: &Context<'gc>, closure: ClosurePtr<'gc>) -> Step<'gc> {
        let error = match self.try_step_closure(cx, closure) {
            Ok(step) => return step,
            Err(error) => error,
        };

        let current_try = loop {
            if let Some(current_try) = self.current_frame.current_try.take() {
                break current_try;
            }
            if self.call_stack.is_empty() {
                // FIXME: error thrown and not caught at the top-level of this fiber.
                //        still not sure what to do here...
                todo!()
            }
            self.pop_frame();
        };

        self.current_frame.pc = current_try.pc;
        self.stack.truncate(current_try.stack_len);

        self.stack.push(error.into());

        Step::Continue
    }

    fn try_step_closure(
        &mut self,
        cx: &Context<'gc>,
        closure: ClosurePtr<'gc>,
    ) -> Result<Step<'gc>, ErrorPtr<'gc>> {
        loop {
            let instruction = closure.function().instruction(self.current_frame.pc);
            self.current_frame.pc += 1;

            match instruction.opcode() {
                opcode::NO_OP => {}

                opcode::NIL => self.stack.push(Value::NIL),
                opcode::TRUE => self.stack.push(Value::TRUE),
                opcode::FALSE => self.stack.push(Value::FALSE),
                opcode::INT => self.stack.push((instruction.operand() as i64).into()),
                opcode::CONST => self.stack.push(
                    closure
                        .function()
                        .constant(instruction.operand() as usize)
                        .into(),
                ),

                opcode::ADD => self.try_int_or_float_op(cx, |a, b| a + b, |a, b| a + b)?,
                opcode::SUB => self.try_int_or_float_op(cx, |a, b| a - b, |a, b| a - b)?,
                opcode::MUL => self.try_int_or_float_op(cx, |a, b| a * b, |a, b| a * b)?,
                opcode::DIV => self.try_int_or_float_op(cx, |a, b| a / b, |a, b| a / b)?,
                opcode::MOD => self.try_int_op(cx, |a, b| a % b)?,

                opcode::RETURN => return Ok(Step::Return(self.pop())),

                _ => unreachable!(),
            }
        }
    }

    fn try_int_or_float_op<I, F>(
        &mut self,
        cx: &Context<'gc>,
        int_op: I,
        float_op: F,
    ) -> Result<(), ErrorPtr<'gc>>
    where
        I: Fn(i64, i64) -> i64,
        F: Fn(f64, f64) -> f64,
    {
        let b = self.pop();
        let a = self.pop();
        let result = if let (Ok(a), Ok(b)) = (a.try_into::<f64>(cx), b.try_into::<f64>(cx)) {
            float_op(a, b).into()
        } else if let (Ok(a), Ok(b)) = (a.try_into::<f64>(cx), b.try_into::<i64>(cx)) {
            float_op(a, b as f64).into()
        } else if let (Ok(a), Ok(b)) = (a.try_into::<i64>(cx), b.try_into::<f64>(cx)) {
            float_op(a as f64, b).into()
        } else {
            int_op(a.try_into(cx)?, b.try_into(cx)?).into()
        };
        self.stack.push(result);
        Ok(())
    }

    fn try_int_op<F>(&mut self, cx: &Context<'gc>, op: F) -> Result<(), ErrorPtr<'gc>>
    where
        F: Fn(i64, i64) -> i64,
    {
        let b = self.pop();
        let a = self.pop();
        self.stack.push(op(a.try_into(cx)?, b.try_into(cx)?).into());
        Ok(())
    }

    fn pop_frame(&mut self) {
        self.current_frame = self
            .call_stack
            .pop()
            .ok_or_else(|| EngineError::CallStackUnderflow)
            .unwrap();
    }

    fn pop(&mut self) -> Value<'gc> {
        self.stack
            .pop()
            .ok_or_else(|| EngineError::StackUnderflow)
            .unwrap()
    }
}

pub enum Step<'gc> {
    Continue,
    Yield(Value<'gc>),
    Return(Value<'gc>),
}

#[derive(Collect, Debug)]
#[collect(no_drop)]
struct Frame<'gc> {
    steppable: Steppable<'gc>,
    pc: usize,
    stack_bottom: usize,
    current_try: Option<Try>,
}

impl<'gc> Frame<'gc> {
    pub fn new_closure(closure: ClosurePtr<'gc>, stack_bottom: usize) -> Self {
        Self {
            steppable: Steppable::Closure(closure),
            pc: 0,
            stack_bottom,
            current_try: None,
        }
    }
}

#[derive(Collect, Debug)]
#[collect(no_drop)]
enum Steppable<'gc> {
    Closure(ClosurePtr<'gc>),
}

#[derive(Collect, Debug)]
#[collect(no_drop)]
struct Try {
    pc: usize,
    stack_len: usize,
}
