use std::{cell::RefCell, collections::HashMap};

use gc_arena::{Gc, Mutation};

pub struct StringPool<'gc> {
    strings: RefCell<HashMap<String, Gc<'gc, String>>>,
}

impl<'gc> StringPool<'gc> {
    pub fn new() -> Self {
        StringPool {
            strings: RefCell::new(HashMap::new()),
        }
    }

    pub fn intern(&self, mc: &Mutation<'gc>, string: &str) -> Gc<'gc, String> {
        self.strings
            .borrow_mut()
            .entry(string.to_string())
            .or_insert_with(|| Gc::new(mc, string.to_string()))
            .clone()
    }

    pub fn get(&self, string: &str) -> Option<Gc<'gc, String>> {
        self.strings.borrow().get(string).cloned()
    }
}
