use crate::{
    compile::Compiler, env::Environment, error::Error, fiber::FiberValue, gc::Heap,
    native::NativeModule, value::Value,
};

pub struct Engine<'gc> {
    heap: Heap<'gc>,
    env: Environment<'gc>,
    compiler: Compiler,
}

impl<'gc> Engine<'gc> {
    pub fn new() -> Engine<'gc> {
        Engine {
            heap: Heap::new(),
            env: Environment::new(),
            compiler: Compiler {},
        }
    }

    pub fn load_native_module<M>(&self, path: &str) -> Result<Value<'gc>, Error>
    where
        M: NativeModule,
    {
        Ok(Value::Nil)
    }

    pub async fn load_module(&self, path: &str) -> Result<Value<'gc>, Error> {
        Ok(Value::Nil)
    }

    pub async fn execute_str(&mut self, path: &str, source: &str) -> Result<Value<'gc>, Error> {
        let function = self.compiler.compile(&self.env, &self.heap, source)?;
        let fiber = FiberValue::new_in(&self.heap, function);
        fiber.run(&self.env, &self.heap).await
    }

    pub fn heap(&self) -> &Heap<'gc> {
        &self.heap
    }
}
