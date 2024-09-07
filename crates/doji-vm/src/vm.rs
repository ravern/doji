use doji_bytecode::Program;

use crate::{fiber::Fiber, gc::Heap};

pub struct Vm<'gc> {
    heap: Heap<'gc>,
}

impl<'gc> Vm<'gc> {
    pub fn new() -> Vm<'gc> {
        Vm { heap: Heap::new() }
    }

    pub fn evaluate(&mut self, program: &Program) {
        let mut fiber = Fiber::new(0);
        fiber.resume(program, &self.heap);
    }
}
