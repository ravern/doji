pub trait Resolver {
    type Error: core::error::Error;

    fn resolve(&self, name: &str) -> Result<Option<&str>, Self::Error>;
}
