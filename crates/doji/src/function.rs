use gc_arena::{Collect, Gc};

#[derive(Collect)]
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

#[derive(Collect)]
#[collect(no_drop)]
pub struct Instruction(u32);

impl Instruction {
    pub fn new(opcode: u8, operand: u32) -> Instruction {
        assert!(operand < 1 << 24, "Operand is too large");

        Instruction(operand << 8 | opcode as u32)
    }

    pub fn opcode(&self) -> u8 {
        (self.0 & 0xFF) as u8
    }

    pub fn operand(&self) -> u32 {
        self.0 >> 8
    }
}

pub mod opcode {
    pub const CONSTANT: u8 = 0;

    pub const ADD: u8 = 0;
    pub const SUB: u8 = 1;
    pub const MUL: u8 = 2;
    pub const DIV: u8 = 3;
    pub const MOD: u8 = 4;
    pub const NEG: u8 = 5;
    pub const EQ: u8 = 6;
    pub const NOT_EQ: u8 = 7;
    pub const LT: u8 = 8;
    pub const LT_EQ: u8 = 9;
    pub const GT: u8 = 10;
    pub const GT_EQ: u8 = 11;
    pub const AND: u8 = 12;
    pub const OR: u8 = 13;
    pub const NOT: u8 = 14;

    pub const TEST: u8 = 14;
    pub const JUMP: u8 = 15;

    pub const CALL: u8 = 17;
    pub const RETURN: u8 = 18;
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

    pub fn constant(&mut self, constant: Constant<'gc>) -> usize {
        self.constants.push(constant);
        self.constants.len() - 1
    }

    pub fn instruction(&mut self, opcode: u8, operand: u32) -> usize {
        self.code.push(Instruction::new(opcode, operand));
        self.code.len() - 1
    }

    pub fn build(self) -> Function<'gc> {
        assert!(self.arity.is_some(), "Arity is not set");

        Function {
            name: self.name,
            arity: self.arity.unwrap(),
            constants: self.constants.into_boxed_slice(),
            code: self.code.into_boxed_slice(),
            upvalues: Box::new([]),
        }
    }
}
