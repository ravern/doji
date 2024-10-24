use std::{
    cell::RefCell,
    fmt::{self, Display, Formatter},
    hash::Hash,
};

use crate::{
    bytecode::{
        self, Arity, ConstantIndex, FunctionIndex, Instruction, InstructionOffset, StackSlot,
    },
    env::Environment,
    error::{Error, ErrorContext, ErrorKind},
    gc::{Handle, Heap, Trace, Tracer},
    value::{ClosureValue, Function, TypeError, UpvalueHandle, Value, ValueType},
};

#[derive(Debug)]
pub struct FiberValue<'gc>(Handle<'gc, RefCell<Fiber<'gc>>>);

impl<'gc> FiberValue<'gc> {
    pub fn new_in(heap: &Heap<'gc>, function: Function) -> FiberValue<'gc> {
        FiberValue::new_with_stack_in(
            heap,
            function.clone(),
            FiberStack::new(Value::closure_in(heap, function, [].into())),
        )
    }

    pub fn new_with_stack_in(
        heap: &Heap<'gc>,
        function: Function,
        stack: FiberStack<'gc>,
    ) -> FiberValue<'gc> {
        FiberValue(
            heap.allocate(RefCell::new(Fiber {
                function: function.clone(),
                instruction_offset: InstructionOffset::from(0),
                stack,
            }))
            .as_handle(),
        )
    }

    pub async fn run(&self, env: &Environment<'gc>, heap: &Heap<'gc>) -> Result<Value<'gc>, Error> {
        self.0.root().borrow_mut().run(env, heap).await
    }
}

impl<'gc> Trace<'gc> for FiberValue<'gc> {
    fn trace(&self, tracer: &Tracer) {
        tracer.trace_handle(&self.0);
    }
}

impl<'gc> Clone for FiberValue<'gc> {
    fn clone(&self) -> Self {
        FiberValue(Handle::clone(&self.0))
    }
}

impl<'gc> PartialEq for FiberValue<'gc> {
    fn eq(&self, other: &Self) -> bool {
        Handle::ptr_eq(&self.0, &other.0)
    }
}

impl<'gc> Eq for FiberValue<'gc> {}

impl<'gc> Hash for FiberValue<'gc> {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        Handle::as_ptr(&self.0).hash(state);
    }
}

enum FiberStep<'gc> {
    Step,
    Done(Value<'gc>),
}

#[derive(Debug)]
struct Fiber<'gc> {
    function: Function,
    instruction_offset: InstructionOffset,
    stack: FiberStack<'gc>,
}

impl<'gc> Fiber<'gc> {
    async fn run(&mut self, env: &Environment<'gc>, heap: &Heap<'gc>) -> Result<Value<'gc>, Error> {
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
        self.advance_code_offset();
        match instruction {
            Instruction::Noop => {}

            Instruction::Nil => self.stack_push(Value::Nil),
            Instruction::True => self.stack_push(Value::Bool(true)),
            Instruction::False => self.stack_push(Value::Bool(false)),
            Instruction::List => self.stack_push(Value::list_in(heap)),
            Instruction::Map => self.stack_push(Value::map_in(heap)),

            Instruction::Int(int) => self.stack_push(Value::Int(int.into_usize() as i64)),

            Instruction::Constant(index) => {
                let constant = self.constant(env, index)?;
                self.stack_push(constant)
            }
            Instruction::Closure(index) => {
                let function = self.function(env, index)?;
                let upvalues = function
                    .upvalues()
                    .iter()
                    .map(|upvalue| {
                        let upvalue = self.capture_upvalue(heap, upvalue)?;
                        self.stack.push_upvalue(upvalue.clone());
                        Ok(upvalue)
                    })
                    .collect::<Result<Box<[_]>, _>>()?;
                self.stack_push(Value::closure_in(heap, function, upvalues));
            }

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
                        self.advance_code_offset();
                    }
                } else {
                    return Err(self.error(ErrorKind::WrongType(TypeError {
                        expected: [ValueType::Bool].into(),
                        found: value.ty(),
                    })));
                }
            }
            Instruction::Jump(offset) => {
                self.instruction_offset = offset;
            }

            Instruction::Call(arity) => {
                let value_slot = StackSlot::from(self.stack.size() - (arity.into_usize()) - 1);
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
                        self.instruction_offset = self.stack.pop_frame().unwrap();
                    }
                    _ => {
                        return Err(self.error(ErrorKind::WrongType(TypeError {
                            expected: [ValueType::Closure, ValueType::NativeFunction].into(),
                            found: value.ty(),
                        })));
                    }
                }
            }
            Instruction::Return => {
                if let Some(offset) = self.stack.pop_frame() {
                    self.instruction_offset = offset;
                    self.function = self.stack_base_as_closure()?.function();
                } else {
                    return Ok(FiberStep::Done(self.stack_pop()?));
                }
            }

            Instruction::UpvalueLoad(index) => {
                let closure = self.stack_base_as_closure()?;
                let upvalue = closure
                    .upvalue(index)
                    .ok_or_else(|| self.error(ErrorKind::UpvalueIndex(index)))?;
                let value = upvalue.get_in(&self.stack).ok_or_else(|| {
                    self.error(ErrorKind::AbsoluteStackSlot(upvalue.slot().unwrap()))
                })?;
                self.stack_push(value);
            }
            Instruction::UpvalueStore(index) => {
                let closure = self.stack_base_as_closure()?;
                let upvalue = closure
                    .upvalue(index)
                    .ok_or_else(|| self.error(ErrorKind::UpvalueIndex(index)))?;
                let value = self.stack_pop()?;
                upvalue.set_in(&mut self.stack, value);
            }
            Instruction::UpvalueClose => {
                self.stack
                    .close_upvalue(StackSlot::from(self.stack.size() - 1));
            }

            Instruction::ObjectGet => {
                let key = self.stack_pop()?;
                let object = self.stack_pop()?;
                let value = object
                    .get(&key)
                    .map_err(|error| self.error(ErrorKind::WrongType(error)))?;
                self.stack_push(value);
            }
            Instruction::ObjectSet => {
                let value = self.stack_pop()?;
                let key = self.stack_pop()?;
                let object = self.stack_pop()?;
                object
                    .set(key, value.clone())
                    .map_err(|error| self.error(ErrorKind::WrongType(error)))?;
                self.stack_push(value);
            }

            _ => todo!(),
        }

        Ok(FiberStep::Step)
    }

    fn capture_upvalue(
        &mut self,
        heap: &Heap<'gc>,
        upvalue: &bytecode::Upvalue,
    ) -> Result<UpvalueHandle<'gc>, Error> {
        match upvalue {
            bytecode::Upvalue::Local(slot) => Ok(UpvalueHandle::new_in(
                heap,
                self.stack.to_absolute_slot(*slot),
            )),
            bytecode::Upvalue::Upvalue(index) => {
                let closure = self.stack_base_as_closure()?;
                closure
                    .upvalue(*index)
                    .ok_or_else(|| self.error(ErrorKind::UpvalueIndex(*index)))
            }
        }
    }

    fn advance_code_offset(&mut self) {
        self.instruction_offset = InstructionOffset::from(self.instruction_offset.into_usize() + 1);
    }

    fn stack_base_as_closure(&self) -> Result<ClosureValue<'gc>, Error> {
        if let Value::Closure(closure) = self.stack_get(StackSlot::from(0))? {
            Ok(closure)
        } else {
            Err(self.error(ErrorKind::FirstStackSlotNotClosure))
        }
    }

    fn stack_set(&mut self, slot: StackSlot, value: Value<'gc>) -> Result<(), Error> {
        self.stack
            .set(slot, value)
            .ok_or_else(|| self.error(ErrorKind::StackSlot(slot)))?;
        Ok(())
    }

    fn stack_get(&self, slot: StackSlot) -> Result<Value<'gc>, Error> {
        self.stack
            .get(slot)
            .ok_or_else(|| self.error(ErrorKind::StackSlot(slot)))
    }

    fn stack_pop(&mut self) -> Result<Value<'gc>, Error> {
        self.stack
            .pop()
            .ok_or_else(|| self.error(ErrorKind::StackUnderflow))
    }

    fn stack_push(&mut self, value: Value<'gc>) {
        self.stack.push(value);
    }

    fn stack_push_frame(&mut self, arity: Arity) {
        let code_offset = self.instruction_offset.into_usize();
        self.stack.push_frame(arity, code_offset);
        self.instruction_offset = InstructionOffset::from(0);
    }

    fn instruction(&self) -> Result<Instruction, Error> {
        self.function
            .instruction(self.instruction_offset)
            .ok_or_else(|| self.error(ErrorKind::InstructionOffset))
    }

    fn constant(&self, env: &Environment<'gc>, index: ConstantIndex) -> Result<Value<'gc>, Error> {
        env.constant(index)
            .ok_or_else(|| self.error(ErrorKind::ConstantIndex(index)))
    }

    fn function(&self, env: &Environment<'gc>, index: FunctionIndex) -> Result<Function, Error> {
        env.function(index)
            .ok_or_else(|| self.error(ErrorKind::FunctionIndex(index)))
    }

    fn error(&self, kind: ErrorKind) -> Error {
        let context = ErrorContext {
            function: self.function.clone(),
            instruction_offset: InstructionOffset::from(self.instruction_offset.into_usize() - 1),
        };
        Error::new(context, kind)
    }
}

impl<'gc> Trace<'gc> for Fiber<'gc> {
    fn trace(&self, tracer: &Tracer) {
        self.stack.trace(tracer);
    }
}

#[derive(Debug)]
pub struct FiberStack<'gc> {
    base: usize,
    upvalues: Vec<UpvalueHandle<'gc>>,
    values: Vec<Value<'gc>>,
    frames: Vec<StackFrame>,
}

impl<'gc> FiberStack<'gc> {
    pub fn new(initial: Value<'gc>) -> FiberStack<'gc> {
        FiberStack {
            base: 0,
            upvalues: Vec::new(),
            values: vec![initial],
            frames: Vec::new(),
        }
    }

    pub fn size(&self) -> usize {
        self.values.len()
    }

    pub fn get_absolute(&self, slot: AbsoluteStackSlot) -> Option<Value<'gc>> {
        self.values.get(slot.into_usize()).cloned()
    }

    pub fn set_absolute(
        &mut self,
        slot: AbsoluteStackSlot,
        value: Value<'gc>,
    ) -> Option<Value<'gc>> {
        self.values
            .get_mut(slot.into_usize())
            // Set and return the value
            .map(|slot_value| {
                *slot_value = value.clone();
                value
            })
    }

    pub fn get(&self, slot: StackSlot) -> Option<Value<'gc>> {
        self.get_absolute(AbsoluteStackSlot::from_stack_slot(self.base, slot))
    }

    pub fn set(&mut self, slot: StackSlot, value: Value<'gc>) -> Option<Value<'gc>> {
        self.set_absolute(AbsoluteStackSlot::from_stack_slot(self.base, slot), value)
    }

    pub fn push(&mut self, value: Value<'gc>) {
        self.values.push(value);
    }

    pub fn pop(&mut self) -> Option<Value<'gc>> {
        self.values.pop()
    }

    pub fn push_frame(&mut self, arity: Arity, code_offset: usize) {
        self.frames.push(StackFrame {
            stack_base: self.base,
            code_offset,
        });
        self.base = self.values.len() - arity.into_usize() - 1;
    }

    pub fn pop_frame(&mut self) -> Option<InstructionOffset> {
        let frame = self.frames.pop();
        if let Some(frame) = frame {
            self.base = frame.stack_base;
            Some(InstructionOffset::from(frame.code_offset))
        } else {
            None
        }
    }

    pub fn push_upvalue(&mut self, upvalue: UpvalueHandle<'gc>) {
        self.upvalues.push(upvalue);
    }

    pub fn close_upvalue(&mut self, slot: StackSlot) -> Option<Value<'gc>> {
        let mut num_closed = 0;
        for upvalue in self.upvalues.iter().rev() {
            if let Some(upvalue_slot) = upvalue.slot() {
                if upvalue_slot.into_usize() < slot.into_usize() {
                    break;
                }
            }
            upvalue.close_in(self);
            num_closed += 1;
        }
        for _ in 0..num_closed {
            self.upvalues.pop();
        }
        self.pop()
    }

    fn to_absolute_slot(&self, slot: StackSlot) -> AbsoluteStackSlot {
        AbsoluteStackSlot::from_stack_slot(self.base, slot)
    }
}

impl<'gc> Trace<'gc> for FiberStack<'gc> {
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

#[derive(Clone, Copy, Debug)]
pub struct AbsoluteStackSlot(u32);

impl AbsoluteStackSlot {
    pub fn from_stack_slot(base: usize, slot: StackSlot) -> AbsoluteStackSlot {
        AbsoluteStackSlot((base + slot.into_usize()) as u32)
    }

    pub fn into_usize(self) -> usize {
        self.into()
    }
}

impl From<usize> for AbsoluteStackSlot {
    fn from(index: usize) -> AbsoluteStackSlot {
        AbsoluteStackSlot(index as u32)
    }
}

impl Into<usize> for AbsoluteStackSlot {
    fn into(self) -> usize {
        self.0 as usize
    }
}

impl Display for AbsoluteStackSlot {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}
