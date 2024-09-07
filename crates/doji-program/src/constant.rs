use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
};
pub struct ConstantPool<T>
where
    T: Eq + Hash,
{
    indices: HashMap<T, usize>,
    constants: Vec<T>,
}

impl<T> ConstantPool<T>
where
    T: Eq + Hash,
{
    pub fn get(&self, index: usize) -> Option<&T> {
        self.constants.get(index)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ConstantFloat(pub f64);

impl Eq for ConstantFloat {}

impl Hash for ConstantFloat {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.0.to_bits().hash(state)
    }
}
