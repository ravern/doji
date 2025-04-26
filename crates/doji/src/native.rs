use gc_arena::{Collect, Mutation};

use crate::io;

/// A Dōji function implemented natively in Rust.
///
/// Native functions consist of steps which will be executed in order. Each step should run
/// some Rust code, and either yield to an I/O operation, call another function (native or
/// otherwise), or return a value.
#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Native {
    pub arity: usize,
    pub steps: &'static [StepFn],
}

impl Native {
    pub fn builder() -> Builder {
        Builder::new()
    }
}

pub type StepFn = for<'gc> fn(&Mutation<'gc>) -> Step;

pub enum Step {
    Yield(io::Operation),
    Call(usize),
    Return,
}

pub struct Builder {
    arity: Option<usize>,
    steps: Vec<StepFn>,
}

impl Builder {
    pub fn new() -> Self {
        Self {
            arity: None,
            steps: Vec::new(),
        }
    }

    pub fn arity(&mut self, arity: usize) -> &mut Self {
        self.arity = Some(arity);
        self
    }

    pub fn step(&mut self, step: StepFn) -> &mut Self {
        self.steps.push(step);
        self
    }

    pub fn build(self) -> Native {
        Native {
            arity: self.arity.expect("arity is not set"),
            steps: Box::leak(self.steps.into_boxed_slice()),
        }
    }
}
