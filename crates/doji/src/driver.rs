use crate::{context::Context, value::IntoValue};

pub trait Driver {
    type Data: for<'gc> IntoValue<'gc>;
    type Error: core::error::Error + Send;

    fn dispatch<'gc>(&self, cx: &Context<'gc>, op: Operation);
    fn poll<'gc>(&self, cx: &Context<'gc>) -> Option<Response<Self::Data, Self::Error>>;
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
