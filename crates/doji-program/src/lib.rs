use std::{cell::RefCell, collections::HashMap};

pub use crate::{
    constant::ConstantPool,
    module::{Chunk, Module},
    opcode::Opcode,
};

use crate::constant::ConstantFloat;

mod constant;
mod module;
mod opcode;

pub struct Program {
    ints: ConstantPool<i64>,
    floats: ConstantPool<ConstantFloat>,
    strings: ConstantPool<Box<str>>,
    modules: ModuleRegistry,
}

impl Program {
    pub fn int(&self, index: usize) -> Option<i64> {
        self.ints.get(index).copied()
    }

    pub fn float(&self, index: usize) -> Option<f64> {
        self.floats.get(index).map(|f| f.0)
    }

    pub fn strings(&self, index: usize) -> Option<&str> {
        self.strings.get(index).map(|s| &**s)
    }

    pub fn register_module(&self, path: &str, module: Module) {
        self.modules.register(path, module);
    }

    pub fn module(&self, index: usize) -> Option<&Module> {
        self.modules.get(index)
    }
}

struct ModuleRegistry {
    indices: HashMap<Box<str>, usize>,
    modules: RefCell<Vec<Module>>,
}

impl ModuleRegistry {
    pub fn register(&self, path: &str, module: Module) {
        let index = self.modules.borrow().len();
        self.indices.insert(path.into(), index);
        self.modules.borrow_mut().push(module);
    }

    pub fn index(&self, path: &str) -> Option<usize> {
        self.indices.get(path).copied()
    }

    pub fn get(&self, index: usize) -> Option<&Module> {
        self.modules.borrow().get(index)
    }
}
