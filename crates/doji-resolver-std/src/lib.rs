use std::io;

pub struct Resolver {}

impl doji::Resolver for Resolver {
    type Error = io::Error;

    fn resolve(&self, name: &str) -> Result<Option<&str>, Self::Error> {
        todo!()
    }
}

impl Default for Resolver {
    fn default() -> Self {
        Self {}
    }
}
