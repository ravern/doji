use std::{cell::RefCell, hash::Hash};

use crate::{
    code::{CodeOffset, ConstantIndex, Instruction, StackSlot},
    env::Environment,
    error::{Error, ErrorContext, ErrorKind},
    gc::{Handle, Heap, Trace, Tracer},
    value::{Function, Value, ValueType, WrongTypeError},
};

#[derive(Debug)]
pub struct Fiber<'gc> {
    inner: Handle<'gc, RefCell<FiberInner<'gc>>>,
}

impl<'gc> Fiber<'gc> {
    pub fn allocate(heap: &Heap<'gc>, function: Function) -> Fiber<'gc> {
        Fiber::allocate_with_stack(
            heap,
            function.clone(),
            Stack::new(Value::allocate_closure(heap, function)),
        )
    }

    pub fn allocate_with_stack(
        heap: &Heap<'gc>,
        function: Function,
        stack: Stack<'gc>,
    ) -> Fiber<'gc> {
        Fiber {
            inner: heap
                .allocate(RefCell::new(FiberInner {
                    function: function.clone(),
                    code_offset: CodeOffset::from(0),
                    stack,
                }))
                .as_handle(),
        }
    }

    pub async fn run(
        &mut self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
    ) -> Result<Value<'gc>, Error> {
        loop {
            match self.inner.root().borrow_mut().step(env, heap).await? {
                FiberStep::Step => {}
                FiberStep::Done(value) => return Ok(value),
            }
        }
    }
}

impl<'gc> Trace<'gc> for Fiber<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.inner);
    }
}

impl<'gc> Clone for Fiber<'gc> {
    fn clone(&self) -> Self {
        Fiber {
            inner: Handle::clone(&self.inner),
        }
    }
}

impl<'gc> PartialEq for Fiber<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.inner, &other.inner)
    }
}

impl<'gc> Eq for Fiber<'gc> {}

impl<'gc> Hash for Fiber<'gc> {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.inner).hash(state);
    }
}

enum FiberStep<'gc> {
    Step,
    Done(Value<'gc>),
}

#[derive(Debug)]
struct FiberInner<'gc> {
    function: Function,
    code_offset: CodeOffset,
    stack: Stack<'gc>,
}

impl<'gc> FiberInner<'gc> {
    async fn step(
        &mut self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
    ) -> Result<FiberStep<'gc>, Error> {
        macro_rules! binary_op {
            ($op:ident) => {{
                let right = self.stack_pop()?;
                let left = self.stack_pop()?;
                let result = left
                    .$op(&right)
                    .map_err(|error| self.error(ErrorKind::WrongType(error)))?;
                self.stack.push(result);
            }};
        }

        macro_rules! unary_op {
            ($op:ident) => {{
                let value = self.stack_pop()?;
                let result = value
                    .$op()
                    .map_err(|error| self.error(ErrorKind::WrongType(error)))?;
                self.stack.push(result);
            }};
        }

        let instruction = self.instruction()?;

        self.increment_code_offset();

        match instruction {
            Instruction::Noop => {}

            Instruction::Nil => self.stack_push(Value::Nil),
            Instruction::True => self.stack_push(Value::Bool(true)),
            Instruction::False => self.stack_push(Value::Bool(false)),
            Instruction::List => self.stack_push(Value::allocate_list(heap)),
            Instruction::Map => self.stack_push(Value::allocate_map(heap)),

            Instruction::Constant(index) => {
                let constant = self.constant(env, index)?;
                self.stack_push(constant)
            }
            Instruction::Closure(_) => todo!(),

            Instruction::Add => binary_op!(add),
            Instruction::Sub => binary_op!(sub),
            Instruction::Mul => binary_op!(mul),
            Instruction::Div => binary_op!(div),
            Instruction::Rem => binary_op!(rem),
            Instruction::Eq => binary_op!(eq),
            Instruction::Gt => binary_op!(gt),
            Instruction::Gte => binary_op!(gte),
            Instruction::Lt => binary_op!(lt),
            Instruction::Lte => binary_op!(lte),
            Instruction::And => binary_op!(and),
            Instruction::Or => binary_op!(or),
            Instruction::Neg => unary_op!(neg),
            Instruction::Not => unary_op!(not),
            Instruction::BitAnd => binary_op!(bit_and),
            Instruction::BitOr => binary_op!(bit_or),
            Instruction::BitXor => binary_op!(bit_xor),

            Instruction::Load(slot) => self.stack_push(self.stack_get(slot)?),
            Instruction::Store(slot) => {
                let value = self.stack_pop()?;
                self.stack_set(slot, value)?
            }
            Instruction::Duplicate => {
                let value = self.stack_pop()?;
                self.stack_push(value.clone());
                self.stack_push(value);
            }
            Instruction::Pop => {
                self.stack_pop()?;
            }

            Instruction::Test => {
                let value = self.stack_pop()?;
                if let Value::Bool(condition) = value {
                    if condition {
                        self.increment_code_offset();
                    }
                } else {
                    return Err(self.error(ErrorKind::WrongType(WrongTypeError {
                        expected: [ValueType::Bool].into(),
                        found: value.ty(),
                    })));
                }
            }
            Instruction::Jump(offset) => {
                self.code_offset = offset;
            }

            Instruction::Call(arity) => {
                let value_slot = StackSlot::from(self.stack.size() - (arity as usize) - 1);
                let value = self.stack_get(value_slot)?;
                match value {
                    Value::Closure(closure) => {
                        if closure.arity() != arity {
                            return Err(self.error(ErrorKind::WrongArity {
                                expected: closure.arity(),
                                found: arity,
                            }));
                        }
                        self.function = closure.function();
                        self.stack_push_frame(arity);
                    }
                    Value::NativeFunction(native) => {
                        if native.arity() != arity {
                            return Err(self.error(ErrorKind::WrongArity {
                                expected: native.arity(),
                                found: arity,
                            }));
                        }
                        self.stack_push_frame(arity);
                        native.call(env, heap, &mut self.stack)?;
                        self.code_offset = self.stack.pop_frame().unwrap();
                    }
                    _ => {
                        return Err(self.error(ErrorKind::WrongType(WrongTypeError {
                            expected: [ValueType::Closure, ValueType::NativeFunction].into(),
                            found: value.ty(),
                        })));
                    }
                }
            }
            Instruction::Return => {
                if let Some(offset) = self.stack.pop_frame() {
                    self.code_offset = offset;
                } else {
                    return Ok(FiberStep::Done(self.stack_pop()?));
                }
            }

            _ => todo!(),
        }

        Ok(FiberStep::Step)
    }

    fn increment_code_offset(&mut self) {
        self.code_offset = CodeOffset::from(self.code_offset.into_usize() + 1);
    }

    fn stack_set(&mut self, slot: StackSlot, value: Value<'gc>) -> Result<(), Error> {
        self.stack
            .set(slot, value)
            .ok_or_else(|| self.error(ErrorKind::InvalidStackSlot(slot)))?;
        Ok(())
    }

    fn stack_get(&self, slot: StackSlot) -> Result<Value<'gc>, Error> {
        self.stack
            .get(slot)
            .ok_or_else(|| self.error(ErrorKind::InvalidStackSlot(slot)))
    }

    fn stack_pop(&mut self) -> Result<Value<'gc>, Error> {
        self.stack
            .pop()
            .ok_or_else(|| self.error(ErrorKind::StackUnderflow))
    }

    fn stack_push(&mut self, value: Value<'gc>) {
        self.stack.push(value);
    }

    fn stack_push_frame(&mut self, arity: u8) {
        let code_offset = self.code_offset.into_usize();
        self.stack.push_frame(arity, code_offset);
        self.code_offset = CodeOffset::from(0);
    }

    fn instruction(&self) -> Result<Instruction, Error> {
        self.function
            .instruction(self.code_offset)
            .ok_or_else(|| self.error(ErrorKind::CodeOffsetOutOfBounds))
    }

    fn constant(&self, env: &Environment<'gc>, index: ConstantIndex) -> Result<Value<'gc>, Error> {
        env.constant(index)
            .ok_or_else(|| self.error(ErrorKind::InvalidConstantIndex(index)))
    }

    fn error(&self, kind: ErrorKind) -> Error {
        let context = ErrorContext {
            code_offset: CodeOffset::from(self.code_offset.into_usize() - 1),
        };
        Error::new(context, kind)
    }
}

impl<'gc> Trace<'gc> for FiberInner<'gc> {
    fn trace(&self, tracer: &Tracer) {
        self.stack.trace(tracer);
    }
}

#[derive(Debug)]
pub struct Stack<'gc> {
    base: usize,
    values: Vec<Value<'gc>>,
    frames: Vec<StackFrame>,
}

impl<'gc> Stack<'gc> {
    fn new(initial: Value<'gc>) -> Stack<'gc> {
        Stack {
            base: 0,
            values: vec![initial],
            frames: Vec::new(),
        }
    }

    fn size(&self) -> usize {
        self.values.len()
    }

    fn get(&self, slot: StackSlot) -> Option<Value<'gc>> {
        self.values.get(self.base + slot.into_usize()).cloned()
    }

    pub fn set(&mut self, slot: StackSlot, value: Value<'gc>) -> Option<Value<'gc>> {
        self.values
            .get_mut(self.base + slot.into_usize())
            .map(|slot_value| {
                *slot_value = value.clone();
                value
            })
    }

    pub fn push(&mut self, value: Value<'gc>) {
        self.values.push(value);
    }

    pub fn pop(&mut self) -> Option<Value<'gc>> {
        self.values.pop()
    }

    fn push_frame(&mut self, arity: u8, code_offset: usize) {
        self.frames.push(StackFrame {
            stack_base: self.base,
            code_offset,
        });
        self.base = self.values.len() - (arity as usize) - 1;
    }

    fn pop_frame(&mut self) -> Option<CodeOffset> {
        let frame = self.frames.pop();
        if let Some(frame) = frame {
            self.base = frame.stack_base;
            Some(CodeOffset::from(frame.code_offset))
        } else {
            None
        }
    }
}

impl<'gc> Trace<'gc> for Stack<'gc> {
    fn trace(&self, tracer: &Tracer) {
        for value in &self.values {
            value.trace(tracer);
        }
    }
}

#[derive(Debug)]
struct StackFrame {
    stack_base: usize,
    code_offset: usize,
}
