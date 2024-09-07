use crate::{error::Error, gc::Heap, native::NativeModule, value::Value};

mod code;
mod compile;
mod env;
mod error;
mod fiber;
mod gc;
mod native;
mod string;
mod value;
mod vm;

pub struct Engine<'gc> {
    heap: Heap<'gc>,
}

impl<'gc> Engine<'gc> {
    pub fn new() -> Engine<'gc> {
        Engine { heap: Heap::new() }
    }

    pub fn register_module<M>(&self, path: &str) -> Result<(), Error>
    where
        M: NativeModule,
    {
        Ok(())
    }

    pub async fn execute_str(&self, source: &str) -> Result<&Value<'gc>, Error> {
        Ok(&Value::Nil)
    }

    pub async fn execute_file(path: &str) -> Result<&Value<'gc>, Error> {
        Ok(&Value::Nil)
    }
}

// #[cfg(test)]
// mod tests {
//     use super::*;

//     #[test]
//     fn test_engine() {
//         let engine = Engine::new();
//         assert!(engine.register_module::<doji_std::Module>("std").is_ok());
//         assert!(engine.execute_str("").is_ok());
//         assert!(engine.execute_file("").is_ok());
//     }
// }
