use std::path::Path;

use bon::Builder;
use gc_arena::{Arena, Rootable};

use crate::{
    context::Context,
    driver::Driver,
    error::Error,
    state::{State, Step},
    value::TryFromValue,
};

#[derive(Builder)]
pub struct Engine {
    #[builder(skip = Arena::new(|mutation| State::new(mutation)))]
    arena: Arena<Rootable![State<'_>]>,
    #[builder(skip)]
    driver: Driver,
}

impl Engine {
    pub fn enter<T>(&self, f: impl for<'gc> FnOnce(&Context<'gc>) -> T) -> T {
        self.arena
            .mutate(|mutation, state| f(&Context::new(mutation, state)))
    }

    pub fn evaluate_inline<T>(&self, source: impl AsRef<str>) -> Result<T, Error>
    where
        T: for<'gc> TryFromValue<'gc>,
    {
        // Compile and spawn the initial fiber.
        self.enter::<Result<_, Error>>(|cx| {
            let closure = cx.compile(source)?;
            cx.spawn(closure);
            Ok(())
        })?;

        loop {
            // Run one step of the evaluation on the state, and return a non-None value if the
            // evaluation is complete.
            let ret_value = self.enter::<Result<_, Error>>(|cx| match cx.state().step(cx) {
                Step::Continue => Ok(None),
                Step::Yield(id, op) => {
                    self.driver.dispatch(cx, id, op);
                    Ok(None)
                }
                Step::Return(value) => Ok(Some(value.try_into(cx)?)),
            })?;

            // If the evaluation is complete, return the result.
            if let Some(value) = ret_value {
                return Ok(value);
            }

            // Poll the driver for any completed operations, and wake the fibers if we find any.
            // Since waking a fiber doesn't allocate much memory, we are fine to poll to completion
            // in a single arena mutation.
            self.enter(|cx| {
                while let Some((id, res)) = self.driver.poll(cx) {
                    cx.state().wake(cx, id, res);
                }
            });
        }
    }

    pub fn evaluate_file<T>(&self, path: impl AsRef<Path>) -> Result<T, Error>
    where
        T: for<'gc> TryFromValue<'gc>,
    {
        unimplemented!()
    }
}
