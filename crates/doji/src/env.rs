use std::{cell::RefCell, collections::HashMap};

use crate::{
    bytecode::{ConstantIndex, FunctionIndex},
    value::{Function, Value},
};

pub struct Environment<'gc> {
    modules: ModuleRegistry<'gc>,
    constants: ConstantPool<'gc>,
    functions: FunctionPool,
}

impl<'gc> Environment<'gc> {
    pub fn new() -> Environment<'gc> {
        Environment {
            modules: ModuleRegistry::new(),
            constants: ConstantPool::new(),
            functions: FunctionPool::new(),
        }
    }

    pub fn register_module(&self, path: String, module: Value<'gc>) {
        self.modules.register(path, module);
    }

    pub fn module(&self, path: &String) -> Option<Value<'gc>> {
        self.modules.get(path)
    }

    pub fn add_constant(&self, constant: Value<'gc>) -> ConstantIndex {
        self.constants.add(constant)
    }

    pub fn constant(&self, index: ConstantIndex) -> Option<Value<'gc>> {
        self.constants.get(index)
    }

    pub fn add_function(&self, function: Function) -> FunctionIndex {
        self.functions.add(function)
    }

    pub fn function(&self, index: FunctionIndex) -> Option<Function> {
        self.functions.get(index)
    }
}

struct ModuleRegistry<'gc> {
    modules: RefCell<HashMap<String, Value<'gc>>>,
}

impl<'gc> ModuleRegistry<'gc> {
    fn new() -> ModuleRegistry<'gc> {
        ModuleRegistry {
            modules: RefCell::new(HashMap::new()),
        }
    }

    fn register(&self, path: String, module: Value<'gc>) {
        let mut modules = self.modules.borrow_mut();
        modules.insert(path, module);
    }

    fn get(&self, path: &String) -> Option<Value<'gc>> {
        self.modules.borrow().get(path).cloned()
    }
}

struct ConstantPool<'gc> {
    inner: RefCell<ConstantPoolInner<'gc>>,
}

struct ConstantPoolInner<'gc> {
    indices: HashMap<Value<'gc>, ConstantIndex>,
    constants: Vec<Value<'gc>>,
}

impl<'gc> ConstantPool<'gc> {
    fn new() -> ConstantPool<'gc> {
        ConstantPool {
            inner: RefCell::new(ConstantPoolInner {
                indices: HashMap::new(),
                constants: Vec::new(),
            }),
        }
    }

    fn add(&self, constant: Value<'gc>) -> ConstantIndex {
        let mut inner = self.inner.borrow_mut();
        if let Some(&index) = inner.indices.get(&constant) {
            index
        } else {
            let index = ConstantIndex::from(inner.constants.len());
            inner.indices.insert(constant.clone(), index);
            inner.constants.push(constant);
            index
        }
    }

    fn get(&self, index: ConstantIndex) -> Option<Value<'gc>> {
        self.inner
            .borrow()
            .constants
            .get(index.into_usize())
            .cloned()
    }
}

struct FunctionPool {
    functions: RefCell<Vec<Function>>,
}

impl FunctionPool {
    fn new() -> FunctionPool {
        FunctionPool {
            functions: RefCell::new(Vec::new()),
        }
    }

    fn add(&self, function: Function) -> FunctionIndex {
        let mut functions = self.functions.borrow_mut();
        let index = FunctionIndex::from(functions.len());
        functions.push(function);
        index
    }

    fn get(&self, index: FunctionIndex) -> Option<Function> {
        let functions = self.functions.borrow();
        functions.get(index.into_usize()).cloned()
    }
}
