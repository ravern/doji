#[derive(Debug)]
pub struct String(Box<str>);

impl From<&str> for String {
    fn from(value: &str) -> Self {
        String(value.into())
    }
}
