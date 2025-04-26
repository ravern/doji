use std::{
    collections::VecDeque,
    convert::Infallible,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};

use doji::{
    Context,
    driver::{Operation, OperationData, Response},
};

#[derive(Default)]
pub struct Driver {
    response_queue: Arc<Mutex<VecDeque<Response<(), Infallible>>>>,
}

impl doji::Driver for Driver {
    type Data = ();
    type Error = Infallible;

    fn dispatch<'gc>(&self, _cx: &Context<'gc>, op: Operation) {
        match op.data() {
            OperationData::Sleep(duration) => {
                let id = op.id();
                let duration = *duration;
                let response_queue = self.response_queue.clone();
                thread::spawn(move || {
                    thread::sleep(Duration::from_millis(duration as u64));
                    response_queue
                        .lock()
                        .unwrap()
                        .push_back(Response::new(id, Ok(())));
                });
            }
        }
    }

    fn poll<'gc>(&self, _cx: &Context<'gc>) -> Option<Response<Self::Data, Self::Error>> {
        self.response_queue.lock().unwrap().pop_front()
    }
}
