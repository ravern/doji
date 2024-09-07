use crate::{error::Error, gc::Heap, native::NativeModule, value::Value};

pub struct Engine<'gc> {
    heap: Heap<'gc>,
}

impl<'gc> Engine<'gc> {
    pub fn new() -> Engine<'gc> {
        Engine { heap: Heap::new() }
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

    pub async fn execute_str(&self, path: &str, source: &str) -> Result<Value<'gc>, Error> {
        Ok(Value::Nil)
    }

    pub async fn execute_file(path: &str) -> Result<Value<'gc>, Error> {
        Ok(Value::Nil)
    }
}
