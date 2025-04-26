use std::error::Error as StdError;

use crate::value::Value;

pub trait Driver {
    type Error;

    fn start(&self);
    fn execute(&self, op: Operation);
    fn poll(&self) -> Option<Result<Response, Self::Error>>;
}

pub struct Operation {
    fiber: usize,
    data: OperationData,
}

pub enum OperationData {
    Sleep(usize),
}

pub struct Response<'gc> {
    fiber: usize,
    value: Value<'gc>,
}

pub struct DefaultDriver;

impl Driver for DefaultDriver {
    type Error = Box<dyn StdError>;

    fn start(&self) {}

    fn execute(&self, _op: Operation) {}

    fn poll(&self) -> Option<Result<Response, Self::Error>> {
        None
    }
}
