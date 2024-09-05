use std::{
    cell::{Cell, RefCell},
    fmt,
    marker::PhantomData,
    ops::Deref,
    rc::{Rc, Weak},
};

pub use self::trace::Trace;

mod trace;

pub struct Tracer;

impl Tracer {
    pub fn trace_handle<'gc, T>(&self, handle: &Handle<'gc, T>)
    where
        T: Trace<'gc>,
    {
        if let Some(root) = handle.try_root() {
            if !root.object.is_marked() {
                root.object.mark();
                root.object.value.trace(self);
            }
        }
    }
}

pub struct Heap<'gc> {
    objects: RefCell<Vec<Rc<Object<'gc, dyn Trace<'gc>>>>>,
}

impl<'gc> Heap<'gc> {
    pub fn new() -> Heap<'gc> {
        Heap {
            objects: RefCell::new(Vec::new()),
        }
    }

    pub fn allocate<T>(&self, value: T) -> Root<'gc, T>
    where
        T: Trace<'gc>,
    {
        let object = Object::new(value);
        let dyn_object = Rc::clone(&object) as Rc<Object<dyn Trace<'gc>>>;
        self.objects.borrow_mut().push(dyn_object);
        Root::from_object(object)
    }

    pub fn collect(&mut self) {
        let tracer = Tracer;
        let mut objects_mut = self.objects.borrow_mut();

        // Sweep trivial + mark
        objects_mut.retain(|object| {
            if Rc::strong_count(object) == 1 && Rc::weak_count(object) == 0 {
                false
            } else if Rc::strong_count(object) > 1 && !object.is_marked() {
                object.mark();
                object.value.trace(&tracer);
                true
            } else {
                true
            }
        });

        // Sweep
        objects_mut.retain(|object| object.unmark());
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

impl<'gc, T> Clone for Root<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    fn clone(&self) -> Root<'gc, T> {
        Root {
            object: Rc::clone(&self.object),
        }
    }
}

impl<'gc, T> fmt::Debug for Root<'gc, T>
where
    T: fmt::Debug + Trace<'gc> + ?Sized,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Root").field(&self.object).finish()
    }
}

impl<'gc, T> Deref for Root<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    type Target = T;

    fn deref(&self) -> &T {
        &self.object.value
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

    pub fn root(&self) -> Root<'gc, T> {
        self.try_root().expect("dangling handle")
    }

    pub fn try_root(&self) -> Option<Root<'gc, T>> {
        Weak::upgrade(&self.object).map(Root::from_object)
    }

    pub fn as_ptr(&self) -> *const T {
        self.object.as_ptr() as *const T
    }

    pub fn ptr_eq(left: &Handle<'gc, T>, right: &Handle<'gc, T>) -> bool {
        Weak::ptr_eq(&left.object, &right.object)
    }
}

impl<'gc, T> Clone for Handle<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    fn clone(&self) -> Handle<'gc, T> {
        Handle {
            object: Weak::clone(&self.object),
        }
    }
}

impl<'gc, T> fmt::Debug for Handle<'gc, T>
where
    T: fmt::Debug + Trace<'gc> + ?Sized,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Handle").field(&self.object).finish()
    }
}

struct Object<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    phantom: PhantomData<&'gc ()>,
    header: ObjectHeader,
    value: T,
}

impl<'gc, T> Object<'gc, T>
where
    T: Trace<'gc>,
{
    fn new(value: T) -> Rc<Object<'gc, T>> {
        Rc::new(Object {
            phantom: PhantomData,
            header: ObjectHeader::new(),
            value,
        })
    }
}

impl<'gc, T> Object<'gc, T>
where
    T: Trace<'gc> + ?Sized,
{
    fn mark(&self) {
        self.header.is_marked.set(true);
    }

    fn unmark(&self) -> bool {
        self.header.is_marked.replace(false)
    }

    fn is_marked(&self) -> bool {
        self.header.is_marked.get()
    }
}

impl<'gc, T> fmt::Debug for Object<'gc, T>
where
    T: fmt::Debug + Trace<'gc> + ?Sized,
{
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.value.fmt(f)
    }
}

struct ObjectHeader {
    is_marked: Cell<bool>,
}

impl ObjectHeader {
    fn new() -> ObjectHeader {
        ObjectHeader {
            is_marked: Cell::new(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;

    struct Simple(u32);

    impl<'gc> Trace<'gc> for Simple {
        fn trace(&self, _tracer: &Tracer) {}
    }

    struct Composite<'gc> {
        foo: Handle<'gc, Simple>,
        bar: Handle<'gc, Simple>,
    }

    impl<'gc> Trace<'gc> for Composite<'gc> {
        fn trace(&self, tracer: &Tracer) {
            tracer.trace_handle(&self.foo);
            tracer.trace_handle(&self.bar);
        }
    }

    struct Cyclic<'gc> {
        foo: Handle<'gc, RefCell<Option<Cyclic<'gc>>>>,
    }

    impl<'gc> Trace<'gc> for Cyclic<'gc> {
        fn trace(&self, tracer: &Tracer) {
            tracer.trace_handle(&self.foo);
        }
    }

    #[test]
    fn simple() {
        let mut heap = Heap::new();
        let root = heap.allocate(Simple(42));
        let handle = root.as_handle();

        heap.collect();
        assert!(handle.try_root().is_some());

        drop(root);

        heap.collect();
        assert!(handle.try_root().is_none());
    }

    #[test]
    fn composite() {
        let mut heap = Heap::new();

        let foo_handle = heap.allocate(Simple(42)).as_handle();
        let bar_handle = heap.allocate(Simple(43)).as_handle();
        let root = heap.allocate(Composite {
            foo: Handle::clone(&foo_handle),
            bar: Handle::clone(&bar_handle),
        });

        let handle = root.as_handle();

        heap.collect();
        assert!(handle.try_root().is_some());
        assert!(foo_handle.try_root().is_some());
        assert!(bar_handle.try_root().is_some());

        drop(root);

        heap.collect();
        assert!(handle.try_root().is_none());
        assert!(foo_handle.try_root().is_none());
        assert!(bar_handle.try_root().is_none());
    }

    #[test]
    fn cyclic() {
        let mut heap = Heap::new();

        let none_root = heap.allocate(RefCell::new(None)).as_handle();
        let first_root = heap.allocate(RefCell::new(Some(Cyclic { foo: none_root })));
        let second_root = heap.allocate(RefCell::new(Some(Cyclic {
            foo: first_root.as_handle(),
        })));
        *first_root.borrow_mut() = Some(Cyclic {
            foo: second_root.as_handle(),
        });

        let first_handle = first_root.as_handle();
        let second_handle = second_root.as_handle();

        heap.collect();
        assert!(first_handle.try_root().is_some());
        assert!(second_handle.try_root().is_some());

        drop(first_root);

        heap.collect();
        assert!(first_handle.try_root().is_some());
        assert!(second_handle.try_root().is_some());

        drop(second_root);

        heap.collect();
        assert!(first_handle.try_root().is_none());
        assert!(second_handle.try_root().is_none());
    }
}
