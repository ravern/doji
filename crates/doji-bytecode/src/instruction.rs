use crate::operand::{CodeOffset, ConstantIndex, IntImmediate, StackSlot, UpvalueIndex};

#[derive(Clone, Copy)]
pub enum Instruction {
    // Primitives
    Noop,
    Nil {
        to: StackSlot,
    },
    True {
        to: StackSlot,
    },
    False {
        to: StackSlot,
    },
    Int {
        to: StackSlot,
        from: IntImmediate,
    },
    Constant {
        to: StackSlot,
        from: ConstantIndex,
    },

    // Stack operations
    Copy {
        to: StackSlot,
        from: StackSlot,
    },
    Add {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Sub {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Mul {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Div {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Rem {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Eq {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Gt {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Gte {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Lt {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Lte {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    And {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Or {
        to: StackSlot,
        left: StackSlot,
        right: StackSlot,
    },
    Neg {
        to: StackSlot,
        from: StackSlot,
    },
    Not {
        to: StackSlot,
        from: StackSlot,
    },

    // Upvalues
    GetUpvalue {
        to: StackSlot,
        from: UpvalueIndex,
    },
    SetUpvalue {
        to: UpvalueIndex,
        from: StackSlot,
    },
    CloseUpvalue {
        from: StackSlot,
    },

    // Control flow
    Test {
        to: StackSlot,
        from: StackSlot,
    },
    JumpForward {
        to: CodeOffset,
    },
    JumpBackward {
        to: CodeOffset,
    },

    // Function calls
    Call {
        to: StackSlot,
        closure: StackSlot,
        arguments: StackSlot,
    },
    Return,

    // Object operations
    GetField {
        to: StackSlot,
        object: StackSlot,
        key: StackSlot,
    },
    SetField {
        object: StackSlot,
        key: StackSlot,
        value: StackSlot,
    },
    Append {
        object: StackSlot,
        value: StackSlot,
    },
}
