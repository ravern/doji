pub enum RuntimeError {
    InvalidModulePath {
        module_path: Box<str>,
    },
    InvalidProgramCounter {
        module_path: Box<str>,
        program_counter: usize,
    },
    InvalidConstantIndex {
        module_path: Box<str>,
        constant_index: u32,
    },
    InvalidStackIndex {
        module_path: Box<str>,
        stack_index: u16,
    },
    InvalidArgumentType {
        module_path: Box<str>,
    },
}
