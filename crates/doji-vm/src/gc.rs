use std::{
    cell::Cell,
    rc::{Rc, Weak},
};

pub trait Trace<'gc>: 'gc {
    fn trace(&self, tracer: &Tracer);
}

pub struct Tracer;

pub struct Heap<'gc> {
    object_list: Option<Rc<Object<'gc, dyn Trace<'gc>>>>,
}

impl<'gc> Heap<'gc> {
    pub fn new() -> Heap<'gc> {
        Heap { object_list: None }
    }

    pub fn allocate<T>(&mut self, value: T) -> Root<'gc, T>
    where
        T: Trace<'gc>,
    {
        let next_object = self.object_list.take();
        let object = Object::new(value, next_object);
        let dyn_object = Rc::clone(&object) as Rc<Object<dyn Trace<'gc>>>;
        self.object_list = Some(dyn_object);
        Root::from_object(object)
    }

    pub fn collect(&mut self) {
        // 1. Iterate over all objects.
        //     a. If their counts are 1 and 0, just drop them immediately.
        //     b. Otherwise if they're already marked, skip them.
        //     b. Otherwise, call trace to mark them.
        // 2. Iterate over all objects.
        //     a. If they are marked, unmark them.
        //     b. Otherwise, drop them.

        // FIXME: The below doesn't work because we're trying to delete objects while
        //        also trying to skip some of them. I think we should loop on `object.next`
        //        instead of `object` (to perform deletes) and also make `object_list`
        //        always have one dummy item.
        //
        // let mut object_list = self.object_list.take();
        // while let Some(ref object) = object_list {
        //     if Rc::strong_count(object) == 1 && Rc::weak_count(object) == 0 {
        //         object_list = object.header.next_object.take();
        //     } else if object.header.is_marked.get() {
        //         object_list = object.header.next_object.take();
        //     } else {
        //         object.value.trace(&Tracer);
        //         object_list = object.header.next_object.take();
        //     }
        // }
    }
}

pub struct Root<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    object: Rc<Object<'gc, T>>,
}

impl<'gc, T> Root<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    fn from_object(object: Rc<Object<'gc, T>>) -> Root<'gc, T> {
        Root { object }
    }

    pub fn as_handle(&self) -> Handle<'gc, T> {
        Handle::from_object(Rc::downgrade(&self.object))
    }
}

pub struct Handle<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    object: Weak<Object<'gc, T>>,
}

impl<'gc, T> Handle<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    fn from_object(object: Weak<Object<'gc, T>>) -> Handle<'gc, T> {
        Handle { object }
    }

    pub fn try_root(&self) -> Option<Root<'gc, T>> {
        Weak::upgrade(&self.object).map(Root::from_object)
    }
}

struct Object<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    header: ObjectHeader<'gc>,
    value: T,
}

impl<'gc, T> Object<'gc, T>
where
    T: Trace<'gc>,
{
    fn new(value: T, next: Option<Rc<Object<'gc, dyn Trace<'gc>>>>) -> Rc<Object<'gc, T>> {
        Rc::new(Object {
            header: ObjectHeader::new(next),
            value,
        })
    }
}

struct ObjectHeader<'gc> {
    is_marked: Cell<bool>,
    next_object: Cell<Option<Rc<Object<'gc, dyn Trace<'gc>>>>>,
}

impl<'gc> ObjectHeader<'gc> {
    fn new(next: Option<Rc<Object<'gc, dyn Trace<'gc>>>>) -> ObjectHeader<'gc> {
        ObjectHeader {
            is_marked: Cell::new(false),
            next_object: Cell::new(next),
        }
    }
}
