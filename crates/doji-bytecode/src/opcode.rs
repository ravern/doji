pub const OP_NOP: u8 = 0xFF;

pub const OP_EXT: u8 = 0x00;

pub const OP_NIL: u8 = 0x10;
pub const OP_TRUE: u8 = 0x11;
pub const OP_FALSE: u8 = 0x12;
pub const OP_INT: u8 = 0x13;
pub const OP_CONST: u8 = 0x14;

pub const OP_ADD: u8 = 0x20;
pub const OP_SUB: u8 = 0x21;
pub const OP_MUL: u8 = 0x22;
pub const OP_DIV: u8 = 0x23;
pub const OP_REM: u8 = 0x24;
pub const OP_EQ: u8 = 0x25;
pub const OP_GT: u8 = 0x26;
pub const OP_GTE: u8 = 0x27;
pub const OP_LT: u8 = 0x28;
pub const OP_LTE: u8 = 0x29;
pub const OP_AND: u8 = 0x2A;
pub const OP_OR: u8 = 0x2B;
pub const OP_NEG: u8 = 0x2C;
pub const OP_NOT: u8 = 0x2D;

pub const OP_LOAD: u8 = 0x30;
pub const OP_STORE: u8 = 0x31;
pub const OP_DUP: u8 = 0x32;
pub const OP_POP: u8 = 0x33;

pub const OP_LOAD_UPVAL: u8 = 0x40;
pub const OP_STORE_UPVAL: u8 = 0x41;
pub const OP_CLOSE_UPVAL: u8 = 0x42;

pub const OP_TEST: u8 = 0x50;
pub const OP_JUMP: u8 = 0x51;

pub const OP_CALL: u8 = 0x60;
pub const OP_RET: u8 = 0x61;

pub const OP_GET_FIELD: u8 = 0x70;
pub const OP_SET_FIELD: u8 = 0x71;
pub const OP_APPEND: u8 = 0x72;
