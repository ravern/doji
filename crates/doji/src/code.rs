use crate::string::String;

#[derive(Debug)]
pub struct Function {
    path: String,
    name: String,
    arity: u8,
    code: Box<[Instruction]>,
}

impl Function {
    pub fn size(&self) -> usize {
        self.code.len()
    }

    pub fn instruction(&self, offset: usize) -> Option<Instruction> {
        self.code.get(offset).copied()
    }
}

#[derive(Clone, Copy, Debug)]
pub enum Instruction {
    Noop,

    Nil,
    True,
    False,
    Int(i32),
    Const(u32),
    List,
    Map,
    Closure(u32),
    Fiber,
    String(u32),

    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Eq,
    Gt,
    Gte,
    Lt,
    Lte,
    And,
    Or,
    Neg,
    Not,
    BitAnd,
    BitOr,
    BitNot,
    BitXor,

    Load(u32),
    Store(u32),
    Dup,
    Pop,

    Test,
    Jump(u32),

    Call(u32),
    Ret,

    UpvalueLoad(u32),
    UpvalueStore(u32),
    UpvalueClose(u32),

    FiberResume,
    FiberYield,

    ValueLen,
    ValueGet,
    ValueSet,
    ValueAppend,
}

pub struct FunctionBuilder {
    path: String,
    name: String,
    arity: u8,
    code: Vec<Instruction>,
}

impl FunctionBuilder {
    pub fn new(path: String, name: String, arity: u8) -> FunctionBuilder {
        FunctionBuilder {
            path,
            name,
            arity,
            code: Vec::new(),
        }
    }

    pub fn code<I>(mut self, instructions: I) -> FunctionBuilder
    where
        I: IntoIterator<Item = Instruction>,
    {
        self.code.extend(instructions);
        self
    }

    pub fn build(self) -> Function {
        Function {
            path: self.path,
            name: self.name,
            arity: self.arity,
            code: self.code.into(),
        }
    }
}
