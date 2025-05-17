use gc_arena::{Collect, Gc};

use crate::{context::Context, error::EngineError, string::StringPtr, value::Value};

pub type FunctionPtr<'gc> = Gc<'gc, Function<'gc>>;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct Function<'gc> {
    name: Option<StringPtr<'gc>>,
    arity: usize,
    constants: Box<[Constant<'gc>]>,
    code: Box<[Instruction]>,
}

impl<'gc> Function<'gc> {
    pub fn builder() -> FunctionBuilder<'gc> {
        FunctionBuilder::default()
    }

    pub fn arity(&self) -> usize {
        self.arity
    }

    pub fn constant(&self, index: usize) -> Constant<'gc> {
        self.constants
            .get(index)
            .ok_or_else(|| EngineError::InvalidConstantIndex(index))
            .unwrap()
            .clone()
    }

    pub fn instruction(&self, offset: usize) -> Instruction {
        *self
            .code
            .get(offset)
            .ok_or_else(|| EngineError::InvalidInstructionOffset(offset))
            .unwrap()
    }
}

#[derive(Clone, Collect, Debug)]
#[collect(no_drop)]
pub enum Constant<'gc> {
    Int(i64),
    Float(f64),
    String(StringPtr<'gc>),
}

impl<'gc> From<Constant<'gc>> for Value<'gc> {
    fn from(constant: Constant<'gc>) -> Value<'gc> {
        match constant {
            Constant::Int(int) => int.into(),
            Constant::Float(float) => float.into(),
            Constant::String(string) => string.into(),
        }
    }
}

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct Instruction(u32);

impl Instruction {
    pub fn new(op: u8, operand: u32) -> Self {
        assert!(operand < (1 << 24), "operand is too large");
        Self(op as u32 | operand << 8)
    }

    pub fn opcode(&self) -> u8 {
        (self.0 & 0xFF) as u8
    }

    pub fn operand(&self) -> u32 {
        self.0 >> 8
    }
}

pub mod opcode {
    pub const NO_OP: u8 = 0x00;

    pub const NIL: u8 = 0x10;
    pub const TRUE: u8 = 0x11;
    pub const FALSE: u8 = 0x12;
    pub const INT: u8 = 0x13;
    pub const CONST: u8 = 0x14;

    pub const ADD: u8 = 0x20;
    pub const SUB: u8 = 0x21;
    pub const MUL: u8 = 0x22;
    pub const DIV: u8 = 0x23;
    pub const MOD: u8 = 0x24;

    pub const RETURN: u8 = 0x30;
}

#[derive(Default)]
pub struct FunctionBuilder<'gc> {
    name: Option<StringPtr<'gc>>,
    arity: Option<usize>,
    constants: Vec<Constant<'gc>>,
    code: Vec<Instruction>,
}

impl<'gc> FunctionBuilder<'gc> {
    pub fn name(mut self, name: StringPtr<'gc>) -> Self {
        self.name = Some(name);
        self
    }

    pub fn arity(&mut self, arity: usize) {
        self.arity = Some(arity);
    }

    pub fn constant(&mut self, constant: Constant<'gc>) -> usize {
        self.constants.push(constant);
        self.constants.len() - 1
    }

    pub fn instruction(&mut self, op: u8, operand: u32) -> usize {
        self.code.push(Instruction::new(op, operand));
        self.code.len() - 1
    }

    pub fn build(self) -> Function<'gc> {
        Function {
            name: self.name,
            arity: self.arity.expect("arity is required"),
            constants: self.constants.into_boxed_slice(),
            code: self.code.into_boxed_slice(),
        }
    }

    pub fn build_ptr(self, cx: &Context<'gc>) -> FunctionPtr<'gc> {
        Gc::new(cx.mutation(), self.build())
    }
}
