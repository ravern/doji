extern crate alloc;
use alloc::boxed::Box;
use std::error::Error;

use crate::{context::Context, value::IntoValue};

pub struct Driver;

impl Driver {
    pub fn new() -> Self {
        Self
    }

    pub fn dispatch<'a>(&self, cx: &Context<'a>, op: Operation) {
        todo!()
    }

    pub fn poll<'gc, T>(&self, cx: &Context<'gc>) -> Option<Response<T, Box<dyn Error + Send>>>
    where
        T: IntoValue<'gc>,
    {
        todo!()
    }
}

pub struct Operation {
    id: OperationId,
    data: OperationData,
}

impl Operation {
    pub fn id(&self) -> OperationId {
        self.id
    }

    pub fn data(&self) -> &OperationData {
        &self.data
    }
}

#[derive(Copy, Clone)]
pub struct OperationId(usize);

pub enum OperationData {
    Sleep(usize),
}

pub struct Response<D, E> {
    id: OperationId,
    result: Result<D, E>,
}

impl<D, E> Response<D, E> {
    pub fn new(id: OperationId, result: Result<D, E>) -> Self {
        Self { id, result }
    }
}
