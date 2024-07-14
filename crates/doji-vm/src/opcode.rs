#[cfg(target_pointer_width = "32")]
pub type Instruction = u32;
#[cfg(target_pointer_width = "64")]
pub type Instruction = u64;

pub type Opcode = u8;

pub const OP_NOOP: Opcode = 0x00;

pub const OP_NIL: Opcode = 0x10;
pub const OP_TRUE: Opcode = 0x11;
pub const OP_FALSE: Opcode = 0x12;
pub const OP_INT: Opcode = 0x13;
pub const OP_CONST: Opcode = 0x14;

pub const OP_COPY: Opcode = 0x20;

pub const OP_GET_UPVAL: Opcode = 0x30;
pub const OP_SET_UPVAL: Opcode = 0x31;

pub const OP_ADD: Opcode = 0x40;
pub const OP_SUB: Opcode = 0x41;
pub const OP_MUL: Opcode = 0x42;
pub const OP_DIV: Opcode = 0x43;
pub const OP_REM: Opcode = 0x44;

pub const OP_EQ: Opcode = 0x50;
pub const OP_GT: Opcode = 0x51;
pub const OP_GTE: Opcode = 0x52;
pub const OP_LT: Opcode = 0x53;
pub const OP_LTE: Opcode = 0x54;

pub const OP_AND: Opcode = 0x60;
pub const OP_OR: Opcode = 0x61;

pub const OP_NEG: Opcode = 0x70;
pub const OP_NOT: Opcode = 0x71;

pub const OP_TEST: Opcode = 0x80;
pub const OP_JMP_F: Opcode = 0x81;
pub const OP_JMP_B: Opcode = 0x82;

pub const OP_CALL: Opcode = 0x90;

pub const OP_GET_FIELD: Opcode = 0xA0;
pub const OP_SET_FIELD: Opcode = 0xA1;
pub const OP_APPEND: Opcode = 0xA2;
