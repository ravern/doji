use crate::{Error, driver::DefaultDriver, resolver::DefaultResolver};

pub struct Engine<R, D> {
    resolver: R,
    driver: D,
}

impl<R, I> Engine<R, I> {
    pub fn builder() -> Builder<R, I> {
        Builder::default()
    }

    pub fn evaluate_inline<T>(&mut self, source: &str) -> Result<T, Error> {
        todo!()
    }
}

pub struct Builder<R, D> {
    resolver: R,
    driver: D,
}

impl<R, D> Builder<R, D> {
    pub fn resolver(mut self, resolver: R) -> Self {
        self.resolver = resolver;
        self
    }

    pub fn driver(mut self, driver: D) -> Self {
        self.driver = driver;
        self
    }

    pub fn build(self) -> Engine<R, D> {
        Engine {
            resolver: self.resolver,
            driver: self.driver,
        }
    }
}

impl<R, I> Default for Builder<R, I> {
    fn default() -> Self {
        Self {
            resolver: unimplemented!(),
            driver: unimplemented!(),
        }
    }
}
