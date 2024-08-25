use std::collections::HashMap;

pub struct Program {
    pub modules: HashMap<Box<str>, Module>,
}

pub struct Module {
    pub constants: Box<[Constant]>,
    pub code: Box<[Instruction]>,
}

pub enum Constant {
    Int(i64),
    Float(f64),
    String(Box<str>),
}

#[derive(Clone, Copy)]
pub enum Instruction {
    Noop,
    Nil { dest: u16 },
    True { dest: u16 },
    False { dest: u16 },
    Int { dest: u16, value: i32 },
    Const { dest: u16, index: u32 },
    Copy { dest: u16, src: u16 },
    GetUpval { dest: u16, index: u16 },
    SetUpval { dest: u16, index: u16 },
    Add { dest: u16, left: u16, right: u16 },
    Sub { dest: u16, left: u16, right: u16 },
    Mul { dest: u16, left: u16, right: u16 },
    Div { dest: u16, left: u16, right: u16 },
    Rem { dest: u16, left: u16, right: u16 },
    Eq { dest: u16, left: u16, right: u16 },
    Gt { dest: u16, left: u16, right: u16 },
    Gte { dest: u16, left: u16, right: u16 },
    Lt { dest: u16, left: u16, right: u16 },
    Lte { dest: u16, left: u16, right: u16 },
    And { dest: u16, left: u16, right: u16 },
    Or { dest: u16, left: u16, right: u16 },
    Neg { dest: u16, src: u16 },
    Not { dest: u16, src: u16 },
    Test { dest: u16 },
    JumpF { offset: u32 },
    JumpB { offset: u32 },
    Call { dest: u16, func: u16, args: u16 },
    GetField { dest: u16, obj: u16, key: u16 },
    SetField { obj: u16, key: u16, value: u16 },
    Append { obj: u16, value: u16 },
}
