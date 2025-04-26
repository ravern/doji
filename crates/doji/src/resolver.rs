use std::error::Error as StdError;

pub trait Resolver {
    type Error;

    fn resolve(&self, name: &str) -> Result<Option<&str>, Self::Error>;
}

pub struct DefaultResolver;

impl Resolver for DefaultResolver {
    type Error = Box<dyn StdError>;

    fn resolve(&self, name: &str) -> Result<Option<&str>, Self::Error> {
        todo!()
    }
}
