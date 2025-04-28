use bon::Builder;
use gc_arena::{Arena, Rootable};

use crate::{
    compile::compile,
    context::Context,
    driver::Driver,
    error::Error,
    state::State,
    value::{RootValue, TryFromValue, ValueTryInto},
};

#[derive(Builder)]
pub struct Engine {
    #[builder(skip = Arena::new(|mutation| State::new(mutation)))]
    arena: Arena<Rootable![State<'_>]>,
    #[builder(skip = Driver::new())]
    driver: Driver,
}

impl Engine {
    pub fn enter<F, T>(&mut self, f: F) -> T
    where
        F: for<'gc> FnOnce(&Context<'gc>) -> T,
    {
        self.arena
            .mutate(|mutation, state| f(&Context::new(mutation, state)))
    }

    pub fn unroot<T>(&mut self, root: RootValue) -> Result<T, Error>
    where
        T: for<'gc> TryFromValue<'gc>,
    {
        self.enter(|cx| cx.unroot(root).value_try_into(cx).map_err(Error::WrongType))
    }

    pub fn evaluate_inline<T>(&mut self, source: impl AsRef<str>) -> Result<T, Error>
    where
        T: for<'gc> TryFromValue<'gc>,
    {
        loop {
            if let Some(value) = self.enter(|cx| {
                let function = match compile(cx, source.as_ref()) {
                    Ok(function) => function,
                    Err(error) => {
                        unimplemented!()
                    }
                };

                // match cx.state().step(cx) {
                //     Step::Continue => {}
                //     Step::Yield(op) => {
                //         self.driver.dispatch(cx, op);
                //     }
                //     Step::Return(value) => {
                //         return Some(value.value_try_into(cx).map_err(Error::Type));
                //     }
                // };

                None
            }) {
                return value;
            }

            // self.enter(|cx| {
            //     if let Some(res) = self.driver.poll(cx) {
            //         let value = res.result?;
            //         cx.state().wake(cx, res);
            //     }
            // })

            unimplemented!()
        }
    }

    pub fn evaluate_file<T>(&mut self, path: impl AsRef<str>) -> Result<T, Error>
    where
        T: for<'gc> TryFromValue<'gc>,
    {
        unimplemented!()
    }
}
