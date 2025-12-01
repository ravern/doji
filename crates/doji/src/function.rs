use core::fmt::{self, Display, Formatter};

use gc_arena::{Collect, Gc};

use crate::{context::Context, error::EngineError, string::StringPtr, value::Value};

pub type FunctionPtr<'gc> = Gc<'gc, Function<'gc>>;

pub const NO_OPERAND: u32 = 0;

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct Function<'gc> {
    name: Option<StringPtr<'gc>>,
    arity: usize,
    functions: Box<[FunctionPtr<'gc>]>,
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

    pub fn function(&self, index: usize) -> FunctionPtr<'gc> {
        self.functions
            .get(index)
            .ok_or_else(|| EngineError::InvalidFunctionIndex(index))
            .unwrap()
            .clone()
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

impl Display for Instruction {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self.opcode() {
            opcode::NO_OP => write!(f, "NO_OP"),
            opcode::NIL => write!(f, "NIL"),
            opcode::TRUE => write!(f, "TRUE"),
            opcode::FALSE => write!(f, "FALSE"),
            opcode::INT => write!(f, "INT {}", self.operand()),
            opcode::CONST => write!(f, "CONST {}", self.operand()),
            opcode::CLOSURE => write!(f, "CLOSURE {}", self.operand()),
            opcode::ADD => write!(f, "ADD"),
            opcode::SUB => write!(f, "SUB"),
            opcode::MUL => write!(f, "MUL"),
            opcode::DIV => write!(f, "DIV"),
            opcode::MOD => write!(f, "MOD"),
            opcode::RETURN => write!(f, "RETURN"),
            opcode::SPAWN => write!(f, "SPAWN"),
            opcode::YIELD => write!(f, "YIELD"),
            _ => write!(f, "UNKNOWN"),
        }
    }
}

pub mod opcode {
    pub const NO_OP: u8 = 0x00;

    pub const NIL: u8 = 0x10;
    pub const TRUE: u8 = 0x11;
    pub const FALSE: u8 = 0x12;
    pub const INT: u8 = 0x13;
    pub const CONST: u8 = 0x14;
    pub const CLOSURE: u8 = 0x15;

    pub const ADD: u8 = 0x20;
    pub const SUB: u8 = 0x21;
    pub const MUL: u8 = 0x22;
    pub const DIV: u8 = 0x23;
    pub const MOD: u8 = 0x24;

    pub const RETURN: u8 = 0x30;

    pub const SPAWN: u8 = 0x40;
    pub const YIELD: u8 = 0x41;
}

#[derive(Default)]
pub struct FunctionBuilder<'gc> {
    name: Option<StringPtr<'gc>>,
    arity: Option<usize>,
    functions: Vec<FunctionPtr<'gc>>,
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

    pub fn function(&mut self, function: FunctionPtr<'gc>) -> usize {
        self.functions.push(function);
        self.functions.len() - 1
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
            functions: self.functions.into_boxed_slice(),
            constants: self.constants.into_boxed_slice(),
            code: self.code.into_boxed_slice(),
        }
    }

    pub fn build_ptr(self, cx: &Context<'gc>) -> FunctionPtr<'gc> {
        Gc::new(cx.mutation(), self.build())
    }
}
