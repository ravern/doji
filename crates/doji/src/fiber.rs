use gc_arena::{
    Collect, Gc,
    lock::{GcRefLock, RefLock},
};

use crate::{
    closure::ClosurePtr, context::Context, error::EngineError, function::opcode, value::Value,
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
        match self.current_frame.runnable {
            Runnable::Closure(closure) => self.step_closure(cx, closure),
        }
    }

    fn step_closure(&mut self, cx: &Context<'gc>, closure: ClosurePtr<'gc>) -> Step<'gc> {
        loop {
            let instruction = closure.function().instruction(self.current_frame.pc);
            self.current_frame.pc += 1;

            match instruction.opcode() {
                opcode::INT => self.stack.push((instruction.operand() as i64).into()),

                opcode::ADD => {
                    let b: i64 = self
                        .stack
                        .pop()
                        .ok_or(EngineError::StackUnderflow)
                        .unwrap()
                        .try_into(cx)
                        .unwrap_or_else(|_| todo!());
                    let a: i64 = self
                        .stack
                        .pop()
                        .ok_or(EngineError::StackUnderflow)
                        .unwrap()
                        .try_into(cx)
                        .unwrap_or_else(|_| todo!());
                    self.stack.push((a + b).into());
                }

                opcode::RETURN => {
                    let value = self.stack.pop().ok_or(EngineError::StackUnderflow).unwrap();
                    return Step::Return(value);
                }

                _ => unreachable!(),
            }
        }
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
    runnable: Runnable<'gc>,
    pc: usize,
    bottom: usize,
}

impl<'gc> Frame<'gc> {
    pub fn new_closure(closure: ClosurePtr<'gc>, bottom: usize) -> Self {
        Self {
            runnable: Runnable::Closure(closure),
            pc: 0,
            bottom,
        }
    }
}

#[derive(Collect, Debug)]
#[collect(no_drop)]
enum Runnable<'gc> {
    Closure(ClosurePtr<'gc>),
}
