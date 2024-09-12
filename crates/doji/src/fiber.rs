use crate::{
    code::{CodeOffset, ConstantIndex, Instruction, StackSlot},
    env::Environment,
    error::{Error, ErrorContext, ErrorKind},
    gc::Heap,
    value::{Closure, Function, Value, ValueType, WrongTypeError},
};

pub struct Fiber<'gc> {
    function: Function,
    code_offset: CodeOffset,
    stack: Stack<'gc>,
}

enum FiberStep<'gc> {
    Step,
    Done(Value<'gc>),
}

impl<'gc> Fiber<'gc> {
    pub fn allocate(heap: &Heap<'gc>, function: Function) -> Fiber<'gc> {
        Fiber {
            function: function.clone(),
            code_offset: CodeOffset::from(0),
            stack: Stack::new(Value::Closure(Closure::allocate(heap, function))),
        }
    }

    pub fn with_stack(function: Function, stack: Stack<'gc>) -> Fiber<'gc> {
        Fiber {
            function,
            code_offset: CodeOffset::from(0),
            stack,
        }
    }

    pub async fn run(
        &mut self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
    ) -> Result<Value<'gc>, Error> {
        loop {
            match self.step(env, heap).await? {
                FiberStep::Step => {}
                FiberStep::Done(value) => return Ok(value),
            }
        }
    }

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
        self.code_offset = CodeOffset::from(self.code_offset.into_usize() + 1);
        match instruction {
            Instruction::Noop => {}

            Instruction::Nil => self.stack.push(Value::Nil),
            Instruction::True => self.stack.push(Value::Bool(true)),
            Instruction::False => self.stack.push(Value::Bool(false)),
            Instruction::List => self.stack.push(Value::allocate_list(heap)),
            Instruction::Map => self.stack.push(Value::allocate_map(heap)),

            Instruction::Constant(index) => {
                let constant = self.constant(env, index)?;
                self.stack.push(constant)
            }
            Instruction::Closure(_) => todo!(),

            Instruction::Add => binary_op!(add),
            Instruction::Sub => binary_op!(sub),
            Instruction::Mul => binary_op!(mul),
            Instruction::Div => binary_op!(div),
            Instruction::Rem => binary_op!(rem),
            Instruction::Eq => {
                let right = self.stack_pop()?;
                let left = self.stack_pop()?;
                self.stack.push(Value::Bool(left == right));
            }
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

            Instruction::Load(slot) => self.stack.push(self.stack_get(slot)?),
            Instruction::Store(slot) => {
                let value = self.stack_pop()?;
                self.stack_set(slot, value)?
            }
            Instruction::Duplicate => {
                let value = self.stack_pop()?;
                self.stack.push(value.clone());
                self.stack.push(value);
            }
            Instruction::Pop => {
                self.stack_pop()?;
            }

            Instruction::Test => {
                let value = self.stack_pop()?;
                if let Value::Bool(condition) = value {
                    if condition {
                        self.code_offset = CodeOffset::from(self.code_offset.into_usize() + 1);
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
                if let Value::Closure(closure) = value {
                    if closure.arity() != arity {
                        return Err(self.error(ErrorKind::WrongArity {
                            expected: closure.arity(),
                            found: arity,
                        }));
                    }
                    self.stack_push_frame(arity);
                } else {
                    return Err(self.error(ErrorKind::WrongType(WrongTypeError {
                        expected: [ValueType::Closure].into(),
                        found: value.ty(),
                    })));
                }
            }
            Instruction::Return => {
                if let Some(offset) = self.stack.pop_frame() {
                    self.code_offset = offset;
                } else {
                    return Ok(FiberStep::Done(self.stack_pop()?));
                }
            }

            Instruction::FiberYield => {
                smol::future::yield_now().await;
            }

            _ => todo!(),
        }

        Ok(FiberStep::Step)
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

    fn stack_push_frame(&mut self, arity: u8) {
        self.stack.push_frame(arity, self.code_offset.into_usize());
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

pub struct Stack<'gc> {
    base: usize,
    values: Vec<Value<'gc>>,
    frames: Vec<StackFrame>,
}

struct StackFrame {
    stack_base: usize,
    code_offset: usize,
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

    fn set(&mut self, slot: StackSlot, value: Value<'gc>) -> Option<Value<'gc>> {
        self.values
            .get_mut(self.base + slot.into_usize())
            .map(|slot_value| {
                *slot_value = value.clone();
                value
            })
    }

    fn push(&mut self, value: Value<'gc>) {
        self.values.push(value);
    }

    fn pop(&mut self) -> Option<Value<'gc>> {
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
