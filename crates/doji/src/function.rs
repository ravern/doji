use gc_arena::{Collect, Gc};

#[derive(Clone, Collect)]
#[collect(no_drop)]
pub enum Constant<'gc> {
    Int(i64),
    Float(f64),
    String(Gc<'gc, String>),
    Function(Gc<'gc, Function<'gc>>),
}

#[derive(Collect)]
#[collect(no_drop)]
pub struct Function<'gc> {
    pub name: Option<Gc<'gc, String>>,
    pub arity: usize,
    pub constants: Box<[Constant<'gc>]>,
    pub code: Box<[Instruction]>,
    pub upvalues: Box<[Upvalue]>,
}

impl<'gc> Function<'gc> {
    pub fn builder() -> Builder<'gc> {
        Builder::new()
    }
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Instruction(u32);

impl Instruction {
    pub fn new(opcode: u8, operand: u32) -> Instruction {
        assert!(operand < 1 << 24, "operand is too large");

        Instruction(operand << 8 | opcode as u32)
    }

    pub fn opcode(&self) -> u8 {
        (self.0 & 0xFF) as u8
    }

    pub fn operand(&self) -> usize {
        (self.0 >> 8) as usize
    }
}

pub mod opcode {
    pub const NO_OP: u8 = 0x0;

    pub const NIL: u8 = 0x10;
    pub const TRUE: u8 = 0x11;
    pub const FALSE: u8 = 0x12;
    pub const INT: u8 = 0x13;
    pub const CONSTANT: u8 = 0x14;
    pub const CLOSURE: u8 = 0x15;
    pub const LIST: u8 = 0x16;
    pub const MAP: u8 = 0x17;
    pub const NATIVE: u8 = 0x18;

    pub const LOAD: u8 = 0x20;
    pub const STORE: u8 = 0x21;
    pub const POP: u8 = 0x22;

    pub const ADD: u8 = 0x30;
    pub const SUB: u8 = 0x31;
    pub const MUL: u8 = 0x32;
    pub const DIV: u8 = 0x33;
    pub const MOD: u8 = 0x34;
    pub const NEG: u8 = 0x35;
    pub const EQ: u8 = 0x36;
    pub const NOT_EQ: u8 = 0x37;
    pub const LT: u8 = 0x38;
    pub const LT_EQ: u8 = 0x39;
    pub const GT: u8 = 0x3a;
    pub const GT_EQ: u8 = 0x3b;
    pub const AND: u8 = 0x3c;
    pub const OR: u8 = 0x3d;
    pub const NOT: u8 = 0x3e;
    pub const BIT_AND: u8 = 0x3f;
    pub const BIT_OR: u8 = 0x40;
    pub const BIT_XOR: u8 = 0x41;
    pub const BIT_NOT: u8 = 0x42;
    pub const BIT_SHL: u8 = 0x43;
    pub const BIT_SHR: u8 = 0x44;

    pub const TEST: u8 = 0x50;
    pub const JUMP: u8 = 0x51;

    pub const CALL: u8 = 0x60;
    pub const RETURN: u8 = 0x61;

    pub const UPVALUE_LOAD: u8 = 0x70;
    pub const UPVALUE_STORE: u8 = 0x71;
    pub const UPVALUE_CLOSE: u8 = 0x72;
}

#[derive(Collect)]
#[collect(no_drop)]
pub enum Upvalue {
    Local(usize),
    Upvalue(usize),
}

pub struct Builder<'gc> {
    name: Option<Gc<'gc, String>>,
    arity: Option<usize>,
    constants: Vec<Constant<'gc>>,
    code: Vec<Instruction>,
}

impl<'gc> Builder<'gc> {
    pub fn new() -> Self {
        Builder {
            name: None,
            arity: None,
            constants: Vec::new(),
            code: Vec::new(),
        }
    }

    pub fn name(&mut self, name: &Gc<'gc, String>) -> &mut Self {
        self.name = Some(name.clone());
        self
    }

    pub fn arity(&mut self, arity: usize) -> &mut Self {
        self.arity = Some(arity);
        self
    }

    pub fn constant(&mut self, constant: Constant<'gc>) -> usize {
        self.constants.push(constant);
        self.constants.len() - 1
    }

    pub fn instruction(&mut self, opcode: u8, operand: u32) -> usize {
        self.code.push(Instruction::new(opcode, operand));
        self.code.len() - 1
    }

    pub fn build(self) -> Function<'gc> {
        Function {
            name: self.name,
            arity: self.arity.expect("arity is not set"),
            constants: self.constants.into_boxed_slice(),
            code: self.code.into_boxed_slice(),
            upvalues: Box::new([]),
        }
    }
}
