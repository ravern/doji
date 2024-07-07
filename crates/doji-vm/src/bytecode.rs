use std::sync::Arc;

use self::int_types::*;

pub struct Chunk {
    pub constants: Box<[Constant]>,
    pub code: Box<[Instruction]>,
}

pub enum Constant {
    Int(ConstantInt),
    Float(ConstantFloat),
    Closure(ConstantClosure),
}

pub type ConstantInt = SignedLong;
pub type ConstantFloat = Float;

pub struct ConstantClosure {
    pub chunk: Arc<Chunk>,
    pub upvalues: Box<[ConstantUpvalue]>,
}

pub struct ConstantUpvalue {
    pub is_local: bool,
    pub index: UpvalueIndex,
}

pub enum Instruction {
    Noop,

    LoadNil { to: Slot },
    LoadTrue { to: Slot },
    LoadFalse { to: Slot },
    LoadInt { to: Slot, int: IntImmediate },
    LoadConstant { to: Slot, constant: ConstantIndex },

    Copy { to: Slot, from: Slot },

    LoadUpvalue { to: Slot, upvalue: UpvalueIndex },
    StoreUpvalue { upvalue: UpvalueIndex, from: Slot },

    Add { to: Slot, left: Slot, right: Slot },
    Sub { to: Slot, left: Slot, right: Slot },
    Mul { to: Slot, left: Slot, right: Slot },
    Div { to: Slot, left: Slot, right: Slot },
    Rem { to: Slot, left: Slot, right: Slot },

    Eq { to: Slot, left: Slot, right: Slot },
    Gt { to: Slot, left: Slot, right: Slot },
    Gte { to: Slot, left: Slot, right: Slot },
    Lt { to: Slot, left: Slot, right: Slot },
    Lte { to: Slot, left: Slot, right: Slot },

    And { to: Slot, left: Slot, right: Slot },
    Or { to: Slot, left: Slot, right: Slot },

    Neg { to: Slot, from: Slot },
    Not { to: Slot, from: Slot },

    Test { cond: Slot },
    JumpForward { offset: BytecodeOffset },
    JumpBack { offset: BytecodeOffset },

    Call { to: Slot, args: Slot, arity: Arity },

    Get { to: Slot, field: Slot, value: Slot },
    Set { on: Slot, field: Slot, value: Slot },
    Append { on: Slot, value: Slot },
}

pub type Slot = UnsignedShort;
pub type IntImmediate = SignedInt;
pub type ConstantIndex = UnsignedShort;
pub type UpvalueIndex = UnsignedShort;
pub type Arity = UnsignedShort;
pub type BytecodeOffset = UnsignedInt;

#[cfg(target_pointer_width = "32")]
mod int_types {
    pub type UnsignedShort = u8;
    pub type UnsignedInt = u16;
    pub type UnsignedLong = u32;
    pub type SignedShort = i8;
    pub type SignedInt = i16;
    pub type SignedLong = i32;
    pub type Float = f32;
}

#[cfg(target_pointer_width = "64")]
mod int_types {
    pub type UnsignedShort = u16;
    pub type UnsignedInt = u32;
    pub type UnsignedLong = u64;
    pub type SignedShort = i16;
    pub type SignedInt = i32;
    pub type SignedLong = i64;
    pub type Float = f64;
}
