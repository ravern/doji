use crate::{
    code::{CodeOffset, ConstantIndex, Instruction, StackSlot},
    env::Environment,
    error::Error,
    gc::Heap,
    value::{Float, Function, List, Map, Value, ValueType},
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

    pub async fn resume(
        &mut self,
        env: &Environment<'gc>,
        heap: &Heap<'gc>,
    ) -> Result<Value<'gc>, Error> {
        let code_offset = self.code_offset.as_usize();
        while code_offset < self.function.size() {
            self.step(env, heap).await?;
        }
        Ok(self.stack.get(0.into()).unwrap().clone())
    }

    pub async fn step(&mut self, env: &Environment<'gc>, heap: &Heap<'gc>) -> Result<(), Error> {
        macro_rules! bool_op {
            ($op:tt) => {{
                let right = self.stack.pop().unwrap();
                let left = self.stack.pop().unwrap();
                match (left, right) {
                    (Value::Bool(left), Value::Bool(right)) => {
                        let result = left $op right;
                        self.stack.push(Value::Bool(result));
                    }
                    (Value::Bool(_), value) | (value, _) => {
                        return Err(Error::WrongType {
                            code_offset: self.code_offset,
                            expected: [ValueType::Bool].into(),
                            found: value.ty(),
                        });
                    },
                }
            }};
        }

        macro_rules! int_op {
            ($op:tt) => {{
                let right = self.stack_pop()?;
                let left = self.stack_pop()?;
                match (left, right) {
                    (Value::Int(left), Value::Int(right)) => {
                        let result = left $op right;
                        self.stack.push(Value::Int(result));
                    }
                    (Value::Int(_), value) | (value, _) => {
                        return Err(Error::WrongType {
                            code_offset: self.code_offset,
                            expected: [ValueType::Int].into(),
                            found: value.ty(),
                        });
                    },
                }
            }};
        }

        macro_rules! float_op {
            ($op:tt, $res:ident) => {
                float_op!($op, $res, $res)
            };
            ($op:tt, $int_res:ident, $float_res:ident) => {{
                let right = self.stack.pop().unwrap();
                let left = self.stack.pop().unwrap();
                match (left, right) {
                    (Value::Int(left), Value::Int(right)) => {
                        let result = left $op right;
                        self.stack.push(Value::$int_res(result));
                    }
                    (Value::Float(left), Value::Float(right)) => {
                        let result = left.as_f64() $op right.as_f64();
                        self.stack.push(Value::$float_res(result.into()));
                    }
                    (Value::Int(left), Value::Float(right)) => {
                        let result = (left as f64) $op right.as_f64();
                        self.stack.push(Value::$float_res(result.into()));
                    }
                    (Value::Float(left), Value::Int(right)) => {
                        let result = left.as_f64() $op right as f64;
                        self.stack.push(Value::$float_res(result.into()));
                    }
                    (Value::Int(_), value) | (Value::Float(_), value) | (value, _) => {
                        return Err(Error::WrongType {
                            code_offset: self.code_offset,
                            expected: [ValueType::Int, ValueType::Float].into(),
                            found: value.ty(),
                        });
                    },
                }
            }};
        }

        macro_rules! simple_op {
            ($op:tt) => {{
                let right = self.stack.pop().unwrap();
                let left = self.stack.pop().unwrap();
                self.stack.push(Value::Bool(left $op right));
            }};
        }

        macro_rules! unary_float_op {
            ($op:tt) => {{
                let value = self.stack.pop().unwrap();
                match value {
                    Value::Int(value) => self.stack.push(Value::Int($op value)),
                    Value::Float(value) => self.stack.push(Value::Float(($op value.as_f64()).into())),
                    value => {
                        return Err(Error::WrongType {
                            code_offset: self.code_offset,
                            expected: [ValueType::Int, ValueType::Float].into(),
                            found: value.ty(),
                        });
                    }
                }
            }};
        }

        macro_rules! unary_bool_op {
            ($op:tt) => {{
                let value = self.stack.pop().unwrap();
                match value {
                    Value::Bool(value) => self.stack.push(Value::Bool($op value)),
                    value => {
                        return Err(Error::WrongType {
                            code_offset: self.code_offset,
                            expected: [ValueType::Bool].into(),
                            found: value.ty(),
                        });
                    }
                }
            }};
        }

        match self.instruction()? {
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

            Instruction::Add => float_op!(+, Int, Float),
            Instruction::Sub => float_op!(-, Int, Float),
            Instruction::Mul => float_op!(*, Int, Float),
            Instruction::Div => float_op!(/, Int, Float),
            Instruction::Rem => int_op!(%),
            Instruction::Eq => simple_op!(==),
            Instruction::Gt => float_op!(>, Bool),
            Instruction::Gte => float_op!(>=, Bool),
            Instruction::Lt => float_op!(<, Bool),
            Instruction::Lte => float_op!(<=, Bool),
            Instruction::And => bool_op!(&&),
            Instruction::Or => bool_op!(||),
            Instruction::Neg => unary_float_op!(-),
            Instruction::Not => unary_bool_op!(!),
            Instruction::BitAnd => int_op!(&),
            Instruction::BitOr => int_op!(|),
            Instruction::BitXor => int_op!(^),

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

            Instruction::Test => todo!(),
            Instruction::Jump(offset) => {
                self.code_offset = offset;
                return Ok(());
            }

            _ => panic!("Unknown instruction"),
        }

        Ok(())
    }

    fn stack_set(&mut self, slot: StackSlot, value: Value<'gc>) -> Result<(), Error> {
        self.stack
            .set(slot, value)
            .ok_or_else(|| Error::InvalidStackSlot {
                code_offset: self.code_offset,
                slot,
            })?;
        Ok(())
    }

    fn stack_get(&self, slot: StackSlot) -> Result<Value<'gc>, Error> {
        self.stack.get(slot).ok_or_else(|| Error::InvalidStackSlot {
            code_offset: self.code_offset,
            slot,
        })
    }

    fn stack_pop(&mut self) -> Result<Value<'gc>, Error> {
        self.stack.pop().ok_or_else(|| Error::StackUnderflow {
            code_offset: self.code_offset,
        })
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

    fn push(&mut self, frame: CallStackFrame) {
        self.frames.push(frame);
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

    fn get(&self, slot: StackSlot) -> Option<Value<'gc>> {
        self.values.get(self.base + slot.as_usize()).cloned()
    }

    fn set(&mut self, slot: StackSlot, value: Value<'gc>) -> Option<Value<'gc>> {
        self.values
            .get_mut(self.base + slot.as_usize())
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
}
