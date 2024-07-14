use smol::LocalExecutor;

use crate::opcode::Instruction;

pub struct Fiber<'bc> {
    code: &'bc [Instruction],
    pc: usize,
}

impl<'bc> Fiber<'bc> {
    pub fn testing_123() {
        let ex = LocalExecutor::new();

        let code = vec![0, 1, 2, 3];

        smol::block_on(ex.run(async move {
            let task_1 = smol::spawn(async move { Fiber { code: &code, pc: 0 } });
            let task_2 = smol::spawn(async move { Fiber { code: &code, pc: 0 } });
            task_1.await;
            task_2.await;
        }));

        // Need scoped (async) tasks for this to be possible
        // I think we'll just use Rc instead since it is still quite fast
        // LocalExecutor enables non-Send stuff inside async blocks

        // A module is some bytecode + constants. It is just a `[usize]` with
        // offsets. Chunks contain offset of bytecode. The `usize`s are decoded
        // at runtime. This is to make things easier to deal with in Rust (we
        // can pass around an `Rc<[usize]>`) and should still be fast. All stored
        // in one slice for cache locality.

        // Information about what upvalues to capture are stored as a constant.
        // Live upvalues (open or closed) are stored in runtime::Closure
    }
}
